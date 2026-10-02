// Data access of the vision functions (interface + limits). The Supabase
// implementation (caller's JWT for the dossier and its files, service role
// for the journal and the analysis columns) is in supabase_db.ts; tests use
// an in-memory fake.

import type { PlanReading, RoomPhotoAnalysis } from "./validate.ts";

export type VisionKind = "room_photo" | "plan";

/** A room photo the caller can read, with the status of its property. */
export interface PhotoRow {
  id: string;
  property_id: string;
  storage_path: string;
  analysis: unknown;
  property_status: string;
}

/** A document the caller can read, with the status of its property. */
export interface DocumentRow {
  id: string;
  property_id: string;
  kind: string;
  mime_type: string | null;
  storage_path: string;
  extracted: unknown;
  property_status: string;
}

export interface RequestUpdate {
  model?: string;
  tokens_in?: number | null;
  tokens_out?: number | null;
  cost_usd?: number | null;
  ms?: number;
  error?: string | null;
}

/** A downloaded file: its bytes, or why it cannot be used. */
export type Download = Uint8Array | "missing" | "too_large";

/** A reserved request (its journal id), or why none was reserved: the
 * daily quota is used up, or the same photo / plan is being analysed. */
export type Reservation = { id: string } | "quota" | "busy";

export interface VisionDb {
  /** The caller's photo (RLS), or null. */
  photo(id: string): Promise<PhotoRow | null>;
  /** The caller's document (RLS), or null. */
  document(id: string): Promise<DocumentRow | null>;
  /** The file at [path] of the documents bucket, read with the caller's
   * rights, up to [maxBytes]. */
  download(path: string, maxBytes: number): Promise<Download>;
  /** Checks that [targetId] is not being analysed and the caller's daily
   * quota of [kind], and records a request, atomically. */
  reserve(
    kind: VisionKind,
    propertyId: string,
    targetId: string,
    since: Date,
  ): Promise<Reservation>;
  /** Completes the journal row of a request. */
  finish(requestId: string, update: RequestUpdate): Promise<void>;
  /** Stores the analysis of a photo (service role) if its property is
   * still a draft at write time; false otherwise (nothing written). */
  saveAnalysis(photo: PhotoRow, analysis: RoomPhotoAnalysis): Promise<boolean>;
  /** Stores the reading of a plan in `extracted.plan_reading`, keeping the
   * other keys (service role), if its property is still a draft at write
   * time; false otherwise. */
  saveReading(document: DocumentRow, reading: PlanReading): Promise<boolean>;
}

/** Limits (plan §2.2). */
export const VISION_LIMITS = {
  photosPerDay: 200,
  plansPerDay: 10,
  /** Largest image sent to the model. */
  imageBytes: 8 * 1024 * 1024,
  /** Largest JSON body of a request. */
  bodyBytes: 2_000,
  /** Tokens of an answer. */
  roomMaxTokens: 700,
  planMaxTokens: 3_000,
  /** A request in progress for the same target younger than this blocks
   * a new one (older ones are considered dead). */
  busySeconds: 120,
  /** How long a request waits for the result of the same analysis in
   * progress, and how often it looks. */
  busyWaitMs: 20_000,
  busyPollMs: 1_000,
};

/** Start of the current day (UTC) for the daily quotas. */
export function startOfDay(now: Date): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
}
