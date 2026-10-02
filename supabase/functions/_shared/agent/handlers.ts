// Request handlers of agent-transcribe, agent-turn and agent-speech, with
// injected dependencies (tested with fakes in handlers_test.ts).
//
// - agent-transcribe: POST audio bytes (application/octet-stream) with
//   ?property_id=&step=&format=m4a&duration=<s> → {turn_id, transcript}.
// - agent-turn: POST {property_id, step, turn_id? | transcript?,
//   lifestyle_labels?} → {turn_id, reply_fr, patch, facts, pending,
//   lifestyle_items, suggestions, next_field, done}. Never writes the
//   dossier: the app applies `patch` itself (RLS, lock).
// - agent-speech: POST {turn_id} → the turn's reply as audio
//   (application/octet-stream, header x-audio-format: mp3 | wav), once.

import {
  type OpenRouterClient,
  OpenRouterError,
  toBase64,
} from "../openrouter/client.ts";
import {
  audioSeconds,
  isSpeechTooShort,
  pcmToWav,
  repairXingHeader,
  speechFormatFor,
} from "../openrouter/audio.ts";
import { type AgentModels, agentProvider } from "./config.ts";
import { type AgentDb, LIMITS, type PropertyRow, startOfDay } from "./db.ts";
import { buildMessages } from "./prompt.ts";
import { type AgentStep, outputSchema } from "./schema.ts";
import {
  type ModelOutput,
  parseModelOutput,
  validateTurn,
} from "./validate.ts";

/** Reply when the agent's answer stays unreadable after a retry. */
export const ASK_TO_REPEAT =
  "Pardon, je n’ai pas bien saisi. Pouvez-vous répéter, s’il vous plaît ?";

export interface Deps {
  db: AgentDb | null;
  openrouter: OpenRouterClient;
  models: AgentModels;
  now?: () => Date;
}

const AUDIO_FORMATS = ["m4a", "wav", "mp3", "aac", "ogg", "webm", "flac"];

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** An error answer: `{error: code}` (codes the app maps to messages). */
export function failure(code: string, status: number, extra = {}): Response {
  return json({ error: code, ...extra }, status);
}

function isStep(value: unknown): value is AgentStep {
  return value === "technical" || value === "lifestyle";
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The caller's draft property, or an error response. */
async function draftProperty(
  db: AgentDb,
  id: unknown,
): Promise<PropertyRow | Response> {
  if (typeof id !== "string" || !UUID.test(id)) {
    return failure("bad_request", 400);
  }
  const property = await db.property(id);
  if (!property) return failure("not_found", 404);
  if (property.status !== "draft") return failure("locked", 409);
  if (property.property_type === "terrain") return failure("bad_request", 400);
  return property;
}

async function quotaError(
  db: AgentDb,
  now: Date,
  audioSeconds = 0,
): Promise<Response | null> {
  const usage = await db.usageSince(startOfDay(now));
  if (
    usage.turns >= LIMITS.turnsPerDay ||
    usage.audioSeconds + audioSeconds > LIMITS.audioSecondsPerDay
  ) {
    return failure("quota", 429);
  }
  return null;
}

function upstreamError(error: unknown): Response {
  // Never echo upstream bodies to the app; they are logged server-side.
  console.error(error instanceof Error ? error.message : "upstream error");
  return failure("upstream", error instanceof OpenRouterError ? 502 : 500);
}

export async function handleTranscribe(
  request: Request,
  deps: Deps,
): Promise<Response> {
  if (request.method !== "POST") return failure("method", 405);
  const db = deps.db;
  if (!db) return failure("unauthorized", 401);
  const now = deps.now?.() ?? new Date();
  const url = new URL(request.url);
  const step = url.searchParams.get("step");
  const format = url.searchParams.get("format") ?? "m4a";
  const duration = Number(url.searchParams.get("duration") ?? "0");
  if (!isStep(step) || !AUDIO_FORMATS.includes(format)) {
    return failure("bad_request", 400);
  }
  if (
    !Number.isFinite(duration) || duration < 0 ||
    duration > LIMITS.audioSecondsPerTurn + 1
  ) {
    return failure("too_long", 413);
  }
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > LIMITS.audioBytes) return failure("too_long", 413);
  const audio = new Uint8Array(await request.arrayBuffer());
  if (audio.length === 0) return failure("bad_request", 400);
  if (audio.length > LIMITS.audioBytes) return failure("too_long", 413);

  try {
    const property = await draftProperty(
      db,
      url.searchParams.get("property_id"),
    );
    if (property instanceof Response) return property;
    const quota = await quotaError(db, now, duration);
    if (quota) return quota;

    let result;
    try {
      result = await deps.openrouter.transcribe({
        model: deps.models.stt,
        audioBase64: toBase64(audio),
        format: format as "m4a",
        language: "fr",
      });
    } catch (error) {
      return upstreamError(error);
    }
    const transcript = result.text.slice(0, LIMITS.transcriptChars);
    if (!transcript) return failure("empty", 422);
    const session = await db.session(property.id, step);
    const turn = await db.insertTurn({
      session_id: session.id,
      transcript,
      audio_seconds: Math.min(result.seconds ?? duration, 9999),
      stt_model: deps.models.stt,
      stt_ms: result.ms,
      cost_usd: result.cost,
    });
    return json({ turn_id: turn.id, transcript });
  } catch (error) {
    return upstreamError(error);
  }
}

interface TurnBody {
  property_id?: unknown;
  step?: unknown;
  turn_id?: unknown;
  transcript?: unknown;
  lifestyle_labels?: { asset?: unknown; watch_point?: unknown };
}

function labels(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string").slice(0, 20)
      .map((v) => v.slice(0, 140))
    : [];
}

export async function handleTurn(
  request: Request,
  deps: Deps,
): Promise<Response> {
  if (request.method !== "POST") return failure("method", 405);
  const db = deps.db;
  if (!db) return failure("unauthorized", 401);
  const now = deps.now?.() ?? new Date();
  let body: TurnBody;
  try {
    body = await request.json();
  } catch {
    return failure("bad_request", 400);
  }
  const step = body.step;
  if (!isStep(step)) return failure("bad_request", 400);

  try {
    const property = await draftProperty(db, body.property_id);
    if (property instanceof Response) return property;
    const session = await db.session(property.id, step);

    let turn;
    if (typeof body.turn_id === "string") {
      const found = await db.turn(body.turn_id);
      if (!found || found.session.id !== session.id) {
        return failure("not_found", 404);
      }
      turn = found;
    } else {
      const transcript = typeof body.transcript === "string"
        ? body.transcript.trim()
        : "";
      if (!transcript) return failure("bad_request", 400);
      if (transcript.length > LIMITS.transcriptChars) {
        return failure("too_long", 413);
      }
      const quota = await quotaError(db, now);
      if (quota) return quota;
      turn = await db.insertTurn({ session_id: session.id, transcript });
    }

    const history = (await db.recentTurns(session.id, LIMITS.historyTurns + 1))
      .filter((t) => t.id !== turn.id)
      .slice(-LIMITS.historyTurns);
    const saved = step === "lifestyle"
      ? await db.lifestyleLabels(property.id)
      : { asset: [], watch_point: [] };
    const lifestyleLabels = {
      asset: [...saved.asset, ...labels(body.lifestyle_labels?.asset)],
      watch_point: [
        ...saved.watch_point,
        ...labels(body.lifestyle_labels?.watch_point),
      ],
    };
    const currentYear = now.getUTCFullYear();

    const messages = buildMessages({
      step,
      values: property,
      transcript: turn.transcript,
      history,
      lifestyleLabels,
      currentYear,
    });
    // A truncated or invalid JSON answer (seen with Gemini Flash-Lite) is
    // asked again once, with more room; then the seller is asked to repeat.
    let output: ModelOutput | null = null;
    let ms = 0;
    let tokensIn = 0;
    let tokensOut = 0;
    let cost = 0;
    for (const maxTokens of [1500, 3000]) {
      let chat;
      try {
        chat = await deps.openrouter.chat({
          model: deps.models.agent,
          messages,
          jsonSchema: { name: "agent_turn", schema: outputSchema(step) },
          maxTokens,
          temperature: 0,
          provider: agentProvider(deps.models.agent),
        });
      } catch (error) {
        await db.updateTurn(turn.id, { error: "agent_failed" }).catch(() => {});
        console.error(error instanceof Error ? error.message : "agent error");
        return failure("upstream", 502, { turn_id: turn.id });
      }
      ms += chat.ms;
      tokensIn += chat.usage.promptTokens ?? 0;
      tokensOut += chat.usage.completionTokens ?? 0;
      cost += chat.usage.cost ?? 0;
      try {
        output = parseModelOutput(chat.content);
        break;
      } catch {
        console.error("agent: invalid JSON output");
      }
    }
    if (!output) {
      await db.updateTurn(turn.id, {
        reply_fr: ASK_TO_REPEAT,
        error: "invalid_output",
        agent_model: deps.models.agent,
        tokens_in: tokensIn,
        tokens_out: tokensOut,
        agent_ms: ms,
        cost_usd: (turn.cost_usd ?? 0) + cost,
      }).catch(() => {});
      return json({
        turn_id: turn.id,
        transcript: turn.transcript,
        reply_fr: ASK_TO_REPEAT,
        patch: {},
        facts: [],
        pending: [],
        lifestyle_items: [],
        suggestions: {},
        next_field: null,
        done: false,
      });
    }
    const validated = validateTurn(output, {
      step,
      values: property,
      transcript: turn.transcript,
      currentYear,
      lifestyleLabels,
    });
    const reply = output.reply_fr.slice(0, LIMITS.replyChars) ||
      "Pouvez-vous reformuler, s’il vous plaît ?";
    const done = output.done;
    const nextField = output.next_field === "none" ? null : output.next_field;
    await db.updateTurn(turn.id, {
      reply_fr: reply,
      extracted: { ...validated, done, next_field: nextField },
      agent_model: deps.models.agent,
      tokens_in: tokensIn,
      tokens_out: tokensOut,
      agent_ms: ms,
      cost_usd: (turn.cost_usd ?? 0) + cost,
    });
    await db.updateSession(session.id, {
      next_field: nextField?.slice(0, 60) ?? null,
      status: done ? "done" : "active",
    });
    return json({
      turn_id: turn.id,
      transcript: turn.transcript,
      reply_fr: reply,
      patch: validated.patch,
      facts: validated.facts,
      pending: validated.pending,
      lifestyle_items: validated.lifestyle_items,
      suggestions: validated.suggestions,
      next_field: nextField,
      done,
    });
  } catch (error) {
    return upstreamError(error);
  }
}

export async function handleSpeech(
  request: Request,
  deps: Deps,
): Promise<Response> {
  if (request.method !== "POST") return failure("method", 405);
  const db = deps.db;
  if (!db) return failure("unauthorized", 401);
  let body: { turn_id?: unknown };
  try {
    body = await request.json();
  } catch {
    return failure("bad_request", 400);
  }
  if (typeof body.turn_id !== "string" || !UUID.test(body.turn_id)) {
    return failure("bad_request", 400);
  }
  try {
    const turn = await db.turn(body.turn_id);
    if (!turn || !turn.reply_fr) return failure("not_found", 404);
    // Each reply is spoken once: the function is not a free TTS.
    if (turn.tts_ms !== null) return failure("already_spoken", 409);
    const property = await draftProperty(db, turn.session.property_id);
    if (property instanceof Response) return property;

    const model = deps.models.tts;
    const format = speechFormatFor(model);
    let speech;
    try {
      speech = await deps.openrouter.speech({
        model,
        input: turn.reply_fr.slice(0, LIMITS.replyChars),
        voice: deps.models.ttsVoice ?? defaultVoice(model),
        format,
      });
    } catch (error) {
      return upstreamError(error);
    }
    await db.updateTurn(turn.id, { tts_model: model, tts_ms: speech.ms });
    const audio = format === "pcm"
      ? pcmToWav(speech.audio)
      : repairXingHeader(speech.audio);
    const seconds = audioSeconds(audio, format === "pcm" ? "wav" : "mp3");
    // Truncated speech: the app shows the reply as text only.
    if (isSpeechTooShort(seconds, turn.reply_fr.length)) {
      console.error(`agent-speech: ${seconds.toFixed(2)} s is too short`);
      return failure("speech_too_short", 422);
    }
    return new Response(audio as BodyInit, {
      headers: {
        "Content-Type": "application/octet-stream",
        "x-audio-format": format === "pcm" ? "wav" : "mp3",
      },
    });
  } catch (error) {
    return upstreamError(error);
  }
}

/** A French voice of the known TTS models (OPENROUTER_TTS_VOICE wins). */
export function defaultVoice(model: string): string | undefined {
  if (model.startsWith("google/")) return "Kore";
  if (model === "hexgrad/kokoro-82m") return "ff_siwis";
  if (model.startsWith("mistralai/voxtral")) return "fr_marie_neutral";
  return undefined;
}
