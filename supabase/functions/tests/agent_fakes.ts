// Fakes of the voice agent handler tests: an in-memory AgentDb and an
// OpenRouter client answering from a handler.
import { LIMITS } from "../_shared/agent/db.ts";
import { OpenRouterClient } from "../_shared/openrouter/client.ts";
import { DEFAULT_MODELS } from "../_shared/agent/config.ts";
import type {
  AgentDb,
  PropertyRow,
  SessionRow,
  TurnReservation,
  TurnRow,
  TurnUpdate,
} from "../_shared/agent/db.ts";
import type { Deps } from "../_shared/agent/handlers.ts";
import type { AgentStep } from "../_shared/agent/schema.ts";

export const PROPERTY = "11111111-1111-4111-8111-111111111111";
export const OTHER = "22222222-2222-4222-8222-222222222222";

export class FakeDb implements AgentDb {
  properties = new Map<string, PropertyRow>([
    [PROPERTY, { id: PROPERTY, status: "draft", property_type: "maison" }],
  ]);
  sessions: (SessionRow & { next_field?: string | null; status?: string })[] = [];
  // deno-lint-ignore no-explicit-any
  turns: (TurnRow & Record<string, any>)[] = [];
  usage = { turns: 0, audioSeconds: 0 };
  saved = { asset: ["Calme"], watch_point: [] as string[] };
  failInsert = false;

  property(id: string) {
    return Promise.resolve(this.properties.get(id) ?? null);
  }
  lifestyleLabels() {
    return Promise.resolve(this.saved);
  }
  session(propertyId: string, step: AgentStep) {
    let s = this.sessions.find((x) => x.property_id === propertyId && x.step === step);
    if (!s) {
      s = { id: `s${this.sessions.length + 1}`, property_id: propertyId, step };
      this.sessions.push(s);
    }
    return Promise.resolve(s);
  }
  updateSession(
    id: string,
    patch: { next_field?: string | null; status?: string },
  ) {
    Object.assign(this.sessions.find((s) => s.id === id)!, patch);
    return Promise.resolve();
  }
  turn(id: string): Promise<(TurnRow & { session: SessionRow }) | null> {
    const t = this.turns.find((x) => x.id === id);
    if (!t) return Promise.resolve(null);
    const session = this.sessions.find((s) => s.id === t.session_id)!;
    return Promise.resolve({ ...t, session });
  }
  recentTurns(sessionId: string, limit: number) {
    return Promise.resolve(
      this.turns.filter((t) => t.session_id === sessionId).slice(-limit),
    );
  }
  // Synchronous check-and-set, like the conditional SQL: atomic here too.
  reserveTurn(turn: TurnReservation) {
    if (this.failInsert) return Promise.reject(new Error("db: denied"));
    if (
      this.usage.turns + 1 > LIMITS.turnsPerDay ||
      this.usage.audioSeconds + turn.audio_seconds > LIMITS.audioSecondsPerDay
    ) {
      return Promise.resolve(null);
    }
    this.usage = {
      turns: this.usage.turns + 1,
      audioSeconds: this.usage.audioSeconds + turn.audio_seconds,
    };
    const row: TurnRow & Record<string, unknown> = {
      id: `3333333${this.turns.length}-3333-4333-8333-333333333333`,
      session_id: turn.session_id,
      transcript: turn.transcript,
      reply_fr: null,
      extracted: null,
      tts_ms: null,
      cost_usd: null,
      audio_seconds: turn.audio_seconds,
      error: "in_progress",
    };
    this.turns.push(row);
    return Promise.resolve(row);
  }
  claimTurn(id: string) {
    const t = this.turns.find((x) => x.id === id);
    const free = !!t && t.reply_fr === null && t.extracted == null &&
      (t.error == null || t.error === "agent_failed");
    if (free) t.error = "in_progress";
    return Promise.resolve(free);
  }
  claimSpeech(id: string) {
    const t = this.turns.find((x) => x.id === id);
    const free = !!t && t.tts_ms === null && t.reply_fr !== null;
    if (free) t.tts_ms = 0;
    return Promise.resolve(free);
  }
  updateTurn(id: string, patch: TurnUpdate) {
    Object.assign(this.turns.find((t) => t.id === id)!, patch);
    return Promise.resolve();
  }
  usageSince() {
    return Promise.resolve(this.usage);
  }
  markUndone(propertyId: string, ids: string[]) {
    const sessions = this.sessions.filter((s) => s.property_id === propertyId).map((s) => s.id);
    const turns = this.turns.filter((t) => ids.includes(t.id) && sessions.includes(t.session_id));
    for (const t of turns) t.undone = true;
    return Promise.resolve(turns.length);
  }
}

export type Handler = (
  url: string,
  init?: RequestInit,
) => Response | Promise<Response>;

export function deps(
  db: FakeDb | null,
  handler: Handler,
  calls: string[] = [],
  models = DEFAULT_MODELS,
): Deps {
  return {
    db,
    openrouter: new OpenRouterClient({
      apiKey: "k",
      fetch: (url, init) => {
        calls.push(url);
        return Promise.resolve(handler(url, init));
      },
    }),
    models,
    now: () => new Date("2026-10-01T10:00:00Z"),
  };
}

export function audioRequest(query: string, body = new Uint8Array([1, 2, 3])) {
  return new Request(`https://x/agent-transcribe?${query}`, {
    method: "POST",
    body,
  });
}

export function jsonRequest(body: unknown, method = "POST") {
  return new Request("https://x/f", {
    method,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

export const sttOk: Handler = () =>
  Response.json({
    text: "La maison date de 1998",
    usage: { seconds: 3, cost: 0.0002 },
  });
