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
  /** Validated answers, once the agent answered. */
  extracted?: unknown;
  tts_ms: number | null;
  cost_usd: number | null;
}

export interface SessionRow {
  id: string;
  property_id: string;
  step: AgentStep;
}

/** A new turn, recorded only within the caller's daily quota. */
export interface TurnReservation {
  session_id: string;
  transcript: string;
  /** Server-measured audio (0 for a typed transcript). */
  audio_seconds: number;
  since: Date;
}

export type TurnUpdate = Partial<{
  transcript: string;
  audio_seconds: number;
  stt_model: string;
  stt_ms: number;
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
  /**
   * Checks the daily quota and records [turn] atomically (serialised per
   * user), claimed for its first call (`error = 'in_progress'`); null when
   * the quota is used up.
   */
  reserveTurn(turn: TurnReservation): Promise<TurnRow | null>;
  /**
   * Claims the agent call of an existing turn: true for exactly one caller,
   * while the turn has no answer and is not being answered (a failed call,
   * `agent_failed`, can be claimed again).
   */
  claimTurn(id: string): Promise<boolean>;
  /** Claims the speech of a turn (true for exactly one caller, once). */
  claimSpeech(id: string): Promise<boolean>;
  updateTurn(id: string, patch: TurnUpdate): Promise<void>;
  /** The caller's turns and audio seconds since [since]. */
  usageSince(since: Date): Promise<DailyUsage>;
  /** Marks the caller's turns [ids] of [propertyId] as undone by the
   * seller (quality follow-up); returns how many were marked. */
  markUndone(propertyId: string, ids: string[]): Promise<number>;
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
  /** Draft values sent by the app (JSON bytes). */
  draftBytes: 4000,
  /** Rows of the V5c table sent by the app. */
  rooms: 40,
  /** Previous estimates sent by the app. */
  estimates: 5,
  /** Undone turns reported at once. */
  undoneTurns: 50,
};

/** Columns of `properties` the agent reads (no identity data: neither the
 * address nor the owners). */
export const PROPERTY_COLUMNS = [
  "id",
  "status",
  "property_type",
  "ownership_type",
  "special_situations",
  "special_situation_other",
  "property_type_other",
  "land_kind",
  "parking_kind",
  "commercial_use",
  "units_count",
  "purchase_year",
  "purchase_price_eur",
  "self_built",
  "sale_reason",
  "previously_estimated",
  "usable_area_m2",
  "parking_level",
  "parking_features",
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
