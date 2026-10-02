// Request handlers of agent-transcribe, agent-turn and agent-speech, with
// injected dependencies (tested with fakes in handlers_test.ts).
//
// - agent-transcribe: POST audio bytes (application/octet-stream) with
//   ?property_id=&step=&format=m4a[&mode=dictation] → {turn_id,
//   transcript}; the duration is measured server-side (m4a header, size
//   bound, STT usage). mode=dictation (V2 address): transcription only,
//   never sent to the language model nor kept in the journal.
// - agent-turn: POST {property_id, step, turn_id? | transcript?,
//   interactive?, draft?, rooms?, estimates?, last_room_ref?,
//   lifestyle_labels?, undone_turn_ids?} → {turn_id, reply_fr, patch,
//   facts, pending, lifestyle_items, suggestions, entity_ops,
//   confirmations, out_of_step, corrections, notes, cross_step,
//   superseded_ids, next_field, done}. Never writes the dossier: the app
//   applies the answer itself (RLS, lock); what is said for another step is
//   recorded as pending answers (EPIC-16), confirmed later by the seller.
//   A body with only undone_turn_ids marks those turns undone.
//
// V1 (`owners`) has no voice since EPIC-16: the step is refused (400).
// Phone numbers and e-mails are masked in every transcript before it is
// kept or sent to the language model.
// - agent-speech: POST {turn_id} → the turn's reply as audio
//   (application/octet-stream, header x-audio-format: mp3 | wav), once.

import { type OpenRouterClient, OpenRouterError, toBase64 } from "../openrouter/client.ts";
import {
  audioSeconds,
  isSpeechTooShort,
  pcmToWav,
  recordingSeconds,
  repairXingHeader,
  speechFormatFor,
} from "../openrouter/audio.ts";
import { maskContacts } from "./anchors.ts";
import { agentModelFor, type AgentModels, agentProvider } from "./config.ts";
import { type AgentDb, LIMITS, type PropertyRow, startOfDay, type TurnRow } from "./db.ts";
import { VOICE_DEFAULTS } from "./defaults.ts";
import { buildMessages } from "./prompt.ts";
import type { RoomRow } from "./rooms.ts";
import { type AgentStep, isStep, outputSchema, stepSchema, voiceStepsFor } from "./schema.ts";
import { ROOM_LEVELS } from "./steps/rooms.ts";
import {
  type EntitySummaries,
  type EstimateRow,
  formatNumber,
  type ModelOutput,
  parseModelOutput,
  validateTurn,
} from "./validate.ts";

/** Reply when the agent's answer stays unreadable after a retry. */
export const ASK_TO_REPEAT =
  "Pardon, je n’ai pas bien saisi. Pouvez-vous répéter, s’il vous plaît ?";

/** What the journal keeps of a dictated address. */
export const ADDRESS_REMOVED = "[adresse non conservée]";

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

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The caller's draft property, when [step] is voiced for its type, or an
 * error response. */
async function draftProperty(
  db: AgentDb,
  id: unknown,
  step: AgentStep,
): Promise<PropertyRow | Response> {
  if (typeof id !== "string" || !UUID.test(id)) {
    return failure("bad_request", 400);
  }
  const property = await db.property(id);
  if (!property) return failure("not_found", 404);
  if (property.status !== "draft") return failure("locked", 409);
  if (!voiceStepsFor(property.property_type).includes(step)) return failure("bad_request", 400);
  return property;
}

/** 429 when the caller's daily quota is used up: [audioSeconds] more of
 * audio, and a new turn when [newTurn] (otherwise an existing one). */
async function quotaError(
  db: AgentDb,
  now: Date,
  { audioSeconds = 0, newTurn = true } = {},
): Promise<Response | null> {
  const usage = await db.usageSince(startOfDay(now));
  if (
    usage.turns + (newTurn ? 1 : 0) > LIMITS.turnsPerDay ||
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

/** The request body, or null when it exceeds [max] bytes (read as a
 * stream: a missing or false content-length cannot bypass the limit). */
export async function readCapped(request: Request, max: number): Promise<Uint8Array | null> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > max) return null;
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.length;
  }
  return body;
}

/** Largest JSON body of agent-turn / agent-speech. */
const MAX_JSON_BYTES = 16_000;

async function readJson<T>(request: Request): Promise<T | Response> {
  const body = await readCapped(request, MAX_JSON_BYTES);
  if (!body) return failure("too_long", 413);
  try {
    return JSON.parse(new TextDecoder().decode(body)) as T;
  } catch {
    return failure("bad_request", 400);
  }
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
  const mode = url.searchParams.get("mode") ?? "agent";
  // The client's `duration` parameter is ignored: never trusted.
  if (!isStep(step) || !AUDIO_FORMATS.includes(format)) {
    return failure("bad_request", 400);
  }
  // Dictation: the V2 address only (transcription, no agent).
  const dictation = mode === "dictation";
  if (
    (mode !== "agent" && !dictation) ||
    (dictation && (step !== "location" || !VOICE_DEFAULTS.addressDictation))
  ) {
    return failure("bad_request", 400);
  }
  const audio = await readCapped(request, LIMITS.audioBytes);
  if (!audio) return failure("too_long", 413);
  if (audio.length === 0) return failure("bad_request", 400);
  const measured = recordingSeconds(audio);
  if (measured > LIMITS.audioSecondsPerTurn + 1) return failure("too_long", 413);

  try {
    const property = await draftProperty(db, url.searchParams.get("property_id"), step);
    if (property instanceof Response) return property;
    const session = await db.session(property.id, step);
    // Reserved before the STT call, atomically with the quota check: parallel
    // uploads cannot exceed the quota nor multiply the STT calls beyond it.
    const turn = await db.reserveTurn({
      session_id: session.id,
      transcript: "",
      audio_seconds: measured,
      since: startOfDay(now),
    });
    if (!turn) return failure("quota", 429);

    let result;
    try {
      result = await deps.openrouter.transcribe({
        model: deps.models.stt,
        audioBase64: toBase64(audio),
        format: format as "m4a",
        language: "fr",
      });
    } catch (error) {
      await db.updateTurn(turn.id, { error: "stt_failed" }).catch(() => {});
      return upstreamError(error);
    }
    const transcript = maskContacts(result.text).slice(0, LIMITS.transcriptChars);
    // Journaled even when empty: the audio and its cost count in the quotas.
    // A dictated address is never kept, and its turn can never be answered.
    await db.updateTurn(turn.id, {
      transcript: dictation && transcript ? ADDRESS_REMOVED : transcript,
      audio_seconds: Math.min(Math.max(result.seconds ?? 0, measured), 9999),
      stt_model: deps.models.stt,
      stt_ms: result.ms,
      cost_usd: result.cost,
      error: transcript ? (dictation ? "dictation" : null) : "empty",
      ...(dictation ? { extracted: { mode: "dictation" } } : {}),
    });
    if (!transcript) return failure("empty", 422);
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
  interactive?: unknown;
  draft?: unknown;
  rooms?: unknown;
  estimates?: unknown;
  last_room_ref?: unknown;
  lifestyle_labels?: { asset?: unknown; watch_point?: unknown };
  undone_turn_ids?: unknown;
  summary?: unknown;
}

function labels(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string").slice(0, 20)
      .map((v) => v.slice(0, 140))
    : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The screen's unsaved answers of [step] (whitelisted columns, simple
 * values, ≤ 4 KB): known values for the prompt and the rules, never
 * written by the server. The type only comes from V3's own draft. */
export function sanitizeDraft(step: AgentStep, value: unknown): Record<string, unknown> {
  if (!isRecord(value)) return {};
  if (JSON.stringify(value).length > LIMITS.draftBytes) return {};
  const columns = new Set(stepSchema(step).fields.map((f) => f.column));
  const draft: Record<string, unknown> = {};
  for (const [column, raw] of Object.entries(value)) {
    if (!columns.has(column)) continue;
    if (
      raw === null || typeof raw === "boolean" ||
      (typeof raw === "number" && Number.isFinite(raw))
    ) {
      draft[column] = raw;
    } else if (typeof raw === "string") {
      draft[column] = raw.slice(0, 300);
    } else if (Array.isArray(raw)) {
      draft[column] = raw.filter((v): v is string => typeof v === "string").slice(0, 10)
        .map((v) => v.slice(0, 40));
    }
  }
  return draft;
}

function num(value: unknown, min: number, max: number): number | null {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max
    ? value
    : null;
}

function str(value: unknown, max: number): string | null {
  return typeof value === "string" && value.trim() ? value.trim().slice(0, max) : null;
}

/** The V5c table sent by the app (≤ 40 rows, references R1…R40). */
export function sanitizeRooms(value: unknown): RoomRow[] {
  if (!Array.isArray(value)) return [];
  const rooms: RoomRow[] = [];
  for (const raw of value.slice(0, LIMITS.rooms)) {
    if (!isRecord(raw)) continue;
    const ref = typeof raw.ref === "string" && /^R\d{1,2}$/.test(raw.ref) ? raw.ref : null;
    const name = str(raw.name, 60);
    const area = num(raw.area_m2, 0.01, 500);
    if (!ref || !name || area === null || rooms.some((r) => r.ref === ref)) continue;
    rooms.push({
      ref,
      name,
      level: typeof raw.level === "string" && raw.level in ROOM_LEVELS ? raw.level : null,
      area_m2: area,
      floor_covering: str(raw.floor_covering, 30),
      glazing: ["simple", "double", "triple"].includes(raw.glazing as string)
        ? raw.glazing as string
        : null,
      ceiling_height_m: num(raw.ceiling_height_m, 0.01, 99),
      is_annex: raw.is_annex === true,
    });
  }
  return rooms;
}

/** The V3 estimate cards sent by the app (≤ 5, references E1…E5). */
export function sanitizeEstimates(value: unknown): EstimateRow[] {
  if (!Array.isArray(value)) return [];
  const estimates: EstimateRow[] = [];
  for (const raw of value.slice(0, LIMITS.estimates)) {
    if (!isRecord(raw)) continue;
    const ref = typeof raw.ref === "string" && /^E\d$/.test(raw.ref) ? raw.ref : null;
    if (!ref || estimates.some((e) => e.ref === ref)) continue;
    const month = typeof raw.estimated_month === "string" &&
        /^\d{4}-\d{2}-\d{2}$/.test(raw.estimated_month)
      ? raw.estimated_month
      : null;
    estimates.push({
      ref,
      price_eur: num(raw.price_eur, 1, 1_000_000_000),
      estimated_month: month,
      agency_name: str(raw.agency_name, 120),
    });
  }
  return estimates;
}

/** What the previous turn retained, for corrections ("non, plutôt 40"). */
export function lastRetained(turn: TurnRow | undefined): string[] {
  const extracted = turn?.extracted;
  if (!isRecord(extracted)) return [];
  const retained: string[] = [];
  const patch = isRecord(extracted.patch) ? extracted.patch : {};
  for (const [column, value] of Object.entries(patch)) {
    retained.push(`${column} = ${Array.isArray(value) ? value.join(", ") : String(value)}`);
  }
  const ops = Array.isArray(extracted.entity_ops) ? extracted.entity_ops : [];
  for (const op of ops) {
    if (!isRecord(op) || typeof op.label_fr !== "string") continue;
    retained.push(`${op.entity} ${op.op} ${op.target} : ${op.label_fr}`);
  }
  const cross = Array.isArray(extracted.cross_step) ? extracted.cross_step : [];
  for (const item of cross) {
    if (!isRecord(item) || typeof item.label_fr !== "string") continue;
    retained.push(`cross_step ${item.target_step} : ${item.label_fr}`);
  }
  return retained.slice(0, 15);
}

function emptyAnswer(turn: { id: string; transcript: string }, reply: string) {
  return {
    turn_id: turn.id,
    transcript: turn.transcript,
    reply_fr: reply,
    patch: {},
    facts: [],
    pending: [],
    lifestyle_items: [],
    suggestions: {},
    entity_ops: [],
    confirmations: [],
    out_of_step: [],
    corrections: [],
    notes: [],
    cross_step: [],
    superseded_ids: [],
    next_field: null,
    done: false,
  };
}

/** "J’ai noté 9 pièces pour 115 m² habitables. Est-ce correct ?" */
export function roomsSummaryText(rooms: RoomRow[]): string {
  const living = rooms.filter((r) => !r.is_annex).reduce((sum, r) => sum + r.area_m2, 0);
  const annex = rooms.filter((r) => r.is_annex).reduce((sum, r) => sum + r.area_m2, 0);
  const count = rooms.length;
  const pieces = count === 1 ? "1 pièce" : `${count} pièces`;
  const annexes = annex > 0 ? `, plus ${formatNumber(annex)} m² d’annexes` : "";
  return count === 0
    ? "Je n’ai noté aucune pièce. Dictez-moi la première, s’il vous plaît."
    : `J’ai noté ${pieces} pour ${formatNumber(living)} m² habitables${annexes}. Est-ce correct ?`;
}

/** The end of a rooms dictation (plan §3.2): the summary is computed here,
 * without the language model, and journaled as a turn so that
 * agent-speech can say it (once, within the quotas). */
async function roomsSummary(
  db: AgentDb,
  propertyId: string,
  rooms: RoomRow[],
  now: Date,
): Promise<Response> {
  const session = await db.session(propertyId, "rooms");
  const turn = await db.reserveTurn({
    session_id: session.id,
    transcript: "[récapitulatif]",
    audio_seconds: 0,
    since: startOfDay(now),
  });
  if (!turn) return failure("quota", 429);
  const reply = roomsSummaryText(rooms);
  await db.updateTurn(turn.id, {
    reply_fr: reply,
    extracted: { mode: "summary", rooms: rooms.length },
    error: null,
  });
  return json(emptyAnswer({ id: turn.id, transcript: "" }, reply));
}

export async function handleTurn(
  request: Request,
  deps: Deps,
): Promise<Response> {
  if (request.method !== "POST") return failure("method", 405);
  const db = deps.db;
  if (!db) return failure("unauthorized", 401);
  const now = deps.now?.() ?? new Date();
  const body = await readJson<TurnBody>(request);
  if (body instanceof Response) return body;
  if (typeof body !== "object" || body === null) return failure("bad_request", 400);
  const step = body.step;
  if (!isStep(step)) return failure("bad_request", 400);
  const undone = Array.isArray(body.undone_turn_ids)
    ? body.undone_turn_ids.filter((id): id is string => typeof id === "string" && UUID.test(id))
      .slice(0, LIMITS.undoneTurns)
    : [];

  try {
    const property = await draftProperty(db, body.property_id, step);
    if (property instanceof Response) return property;
    if (undone.length) await db.markUndone(property.id, undone);
    if (step === "rooms" && body.summary === true) {
      return await roomsSummary(db, property.id, sanitizeRooms(body.rooms), now);
    }
    if (body.turn_id === undefined && body.transcript === undefined) {
      // Only reporting undone turns.
      return undone.length ? json({ undone: undone.length }) : failure("bad_request", 400);
    }
    const session = await db.session(property.id, step);

    let turn;
    if (body.turn_id !== undefined) {
      if (typeof body.turn_id !== "string" || !UUID.test(body.turn_id)) {
        return failure("bad_request", 400);
      }
      const found = await db.turn(body.turn_id);
      if (!found || found.session.id !== session.id) {
        return failure("not_found", 404);
      }
      const quota = await quotaError(db, now, { newTurn: false });
      if (quota) return quota;
      // Exactly one agent answer per turn: claimed atomically (a failed
      // call may be claimed again).
      if (
        found.reply_fr !== null || found.extracted != null || !(await db.claimTurn(found.id))
      ) {
        return failure("already_answered", 409);
      }
      turn = found;
    } else {
      const transcript = typeof body.transcript === "string"
        ? maskContacts(body.transcript.trim())
        : "";
      if (!transcript) return failure("bad_request", 400);
      if (transcript.length > LIMITS.transcriptChars) {
        return failure("too_long", 413);
      }
      const reserved = await db.reserveTurn({
        session_id: session.id,
        transcript,
        audio_seconds: 0,
        since: startOfDay(now),
      });
      if (!reserved) return failure("quota", 429);
      turn = reserved;
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
    const currentMonth = now.getUTCMonth() + 1;
    const values = { ...property, ...sanitizeDraft(step, body.draft) };
    const rooms = step === "rooms" ? sanitizeRooms(body.rooms) : [];
    const estimates = step === "context" ? sanitizeEstimates(body.estimates) : [];
    const pending = await db.pendingAnswers(property.id);
    const entities: EntitySummaries = VOICE_DEFAULTS.crossStepPrefill
      ? await db.entitySummaries(property.id)
      : { rooms: [], estimates: [] };
    const lastRoomRef = typeof body.last_room_ref === "string" &&
        rooms.some((r) => r.ref === body.last_room_ref)
      ? body.last_room_ref
      : null;
    const model = agentModelFor(deps.models, step);

    const messages = buildMessages({
      step,
      values,
      transcript: turn.transcript,
      history,
      lifestyleLabels,
      currentYear,
      currentMonth,
      rooms,
      estimates,
      pending,
      lastRetained: lastRetained(history.at(-1)),
    });
    // A truncated or invalid JSON answer (seen with Gemini Flash-Lite) is
    // asked again once, with more room; then the seller is asked to repeat.
    let output: ModelOutput | null = null;
    let ms = 0;
    let tokensIn = 0;
    let tokensOut = 0;
    let cost = 0;
    const budget = stepSchema(step).maxTokens;
    for (const maxTokens of [budget, budget * 2]) {
      let chat;
      try {
        chat = await deps.openrouter.chat({
          model,
          messages,
          jsonSchema: { name: "agent_turn", schema: outputSchema(step, values) },
          maxTokens,
          temperature: 0,
          provider: agentProvider(model),
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
        agent_model: model,
        tokens_in: tokensIn,
        tokens_out: tokensOut,
        agent_ms: ms,
        cost_usd: (turn.cost_usd ?? 0) + cost,
      }).catch(() => {});
      return json(emptyAnswer(turn, ASK_TO_REPEAT));
    }
    const validated = validateTurn(output, {
      step,
      values,
      transcript: turn.transcript,
      currentYear,
      currentMonth,
      lifestyleLabels,
      interactive: body.interactive === true,
      rooms,
      lastRoomRef,
      estimates,
      pending,
      entities,
    });
    const reply = maskContacts(output.reply_fr).slice(0, LIMITS.replyChars) ||
      "Pouvez-vous reformuler, s’il vous plaît ?";
    const done = output.done;
    const nextField = output.next_field === "none" ? null : output.next_field;
    // What was said for other steps becomes pending answers (one
    // transaction; beyond the ceiling a row is refused as "full").
    const recorded = await db.recordPending(property.id, turn.id, step, validated.cross_step);
    const crossStep = validated.cross_step.map((item, index) => ({
      id: recorded.ids[index] ?? null,
      ...item,
    }));
    for (const item of crossStep.filter((c) => c.id === null)) {
      validated.rejected.push({ field: `x:${item.field ?? item.kind}`, value: "", reason: "full" });
    }
    const kept = crossStep.filter((c) => c.id !== null);
    await db.updateTurn(turn.id, {
      reply_fr: reply,
      extracted: {
        ...validated,
        cross_step: kept,
        superseded_ids: recorded.superseded,
        done,
        next_field: nextField,
      },
      agent_model: model,
      tokens_in: tokensIn,
      tokens_out: tokensOut,
      agent_ms: ms,
      cost_usd: (turn.cost_usd ?? 0) + cost,
      error: null,
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
      entity_ops: validated.entity_ops,
      confirmations: validated.confirmations,
      out_of_step: validated.out_of_step,
      corrections: validated.corrections,
      notes: validated.notes,
      cross_step: kept,
      superseded_ids: recorded.superseded,
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
  const body = await readJson<{ turn_id?: unknown }>(request);
  if (body instanceof Response) return body;
  if (typeof body?.turn_id !== "string" || !UUID.test(body.turn_id)) {
    return failure("bad_request", 400);
  }
  try {
    const turn = await db.turn(body.turn_id);
    if (!turn || !turn.reply_fr) return failure("not_found", 404);
    const property = await draftProperty(db, turn.session.property_id, turn.session.step);
    if (property instanceof Response) return property;
    const quota = await quotaError(db, deps.now?.() ?? new Date(), {
      newTurn: false,
    });
    if (quota) return quota;
    // Each reply is spoken once, claimed atomically: the function is not a
    // free TTS, even with parallel requests.
    if (turn.tts_ms !== null || !(await db.claimSpeech(turn.id))) {
      return failure("already_spoken", 409);
    }

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
    const audio = format === "pcm" ? pcmToWav(speech.audio) : repairXingHeader(speech.audio);
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
