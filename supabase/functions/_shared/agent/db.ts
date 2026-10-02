// Data access of the voice agent functions (interface + limits). The
// Supabase implementation (caller's JWT, RLS) is in supabase_db.ts; tests
// use an in-memory fake.

import type { AgentStep, PropertyValues } from "./schema.ts";

export interface PropertyRow extends PropertyValues {
  id: string;
  status: string;
  property_type: string | null;
}

export interface TurnRow {
  id: string;
  session_id: string;
  transcript: string;
  reply_fr: string | null;
  tts_ms: number | null;
  cost_usd: number | null;
}

export interface SessionRow {
  id: string;
  property_id: string;
  step: AgentStep;
}

export interface TurnInsert {
  session_id: string;
  transcript: string;
  audio_seconds?: number | null;
  stt_model?: string | null;
  stt_ms?: number | null;
  cost_usd?: number | null;
}

export type TurnUpdate = Partial<{
  reply_fr: string | null;
  extracted: unknown;
  agent_model: string;
  tts_model: string;
  tokens_in: number | null;
  tokens_out: number | null;
  agent_ms: number;
  tts_ms: number;
  cost_usd: number | null;
  error: string | null;
}>;

export interface DailyUsage {
  turns: number;
  audioSeconds: number;
}

export interface AgentDb {
  /** The caller's property (RLS), or null. */
  property(id: string): Promise<PropertyRow | null>;
  /** Labels of the saved lifestyle items, per kind. */
  lifestyleLabels(
    propertyId: string,
  ): Promise<{ asset: string[]; watch_point: string[] }>;
  /** The active session of the property step, created when missing. */
  session(propertyId: string, step: AgentStep): Promise<SessionRow>;
  updateSession(
    id: string,
    patch: { next_field?: string | null; status?: "active" | "done" },
  ): Promise<void>;
  /** The caller's turn with its session, or null. */
  turn(id: string): Promise<(TurnRow & { session: SessionRow }) | null>;
  /** The last [limit] turns of a session, oldest first. */
  recentTurns(sessionId: string, limit: number): Promise<TurnRow[]>;
  insertTurn(turn: TurnInsert): Promise<TurnRow>;
  updateTurn(id: string, patch: TurnUpdate): Promise<void>;
  /** The caller's turns and audio seconds since [since]. */
  usageSince(since: Date): Promise<DailyUsage>;
}

/** Limits (plan §3.5). */
export const LIMITS = {
  turnsPerDay: 120,
  audioSecondsPerDay: 20 * 60,
  audioSecondsPerTurn: 60,
  audioBytes: 1_500_000,
  transcriptChars: 2000,
  replyChars: 600,
  historyTurns: 6,
};

/** Columns of `properties` the agent reads (no identity data). */
export const PROPERTY_COLUMNS = [
  "id",
  "status",
  "property_type",
  "construction_year",
  "orientation",
  "living_area_m2",
  "living_room_area_m2",
  "rooms_count",
  "bedrooms_count",
  "levels",
  "wall_material",
  "adjacency",
  "roof_type",
  "roof_year",
  "heating_systems",
  "heat_pump_type",
  "heat_pump_year",
  "sanitation",
  "outdoor_equipment",
  "pool_type",
  "pool_length_m",
  "pool_width_m",
  "noise_level",
  "overlooking",
  "secret_note",
].join(",");

/** Start of the current day (UTC) for the daily quotas. */
export function startOfDay(now: Date): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
}
