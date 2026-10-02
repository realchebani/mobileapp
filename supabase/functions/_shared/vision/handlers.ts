// Request handlers of vision-room and plan-reader (EPIC-15), with injected
// dependencies (tested with fakes in tests/vision_handlers_test.ts).
//
// - vision-room: POST {photo_id} → {analysis, cached}: the suggestions of
//   the vision AI for one room photo of the caller's draft (room kind,
//   floor covering, glazing, condition notes without figures, personal
//   items, people visible, photo defects), stored in room_photos.analysis.
// - plan-reader: POST {document_id} → {reading, cached}: the rooms and
//   areas printed on a photographed floor plan (a `plan` document, JPEG or
//   PNG) of the caller's draft, stored in property_documents.extracted.
//
// Neither function writes the dossier (rooms, property): the seller accepts
// each suggestion in the app. A photo or a plan is sent to the model once
// (later calls answer from the stored result). Quotas per user and day
// (vision_requests, VISION_LIMITS).

import { type OpenRouterClient, OpenRouterError, toBase64 } from "../openrouter/client.ts";
import { failure, json, readCapped } from "../agent/handlers.ts";
import { VISION_PROVIDER, type VisionModels } from "./config.ts";
import { type Download, startOfDay, VISION_LIMITS, type VisionDb, type VisionKind } from "./db.ts";
import { PLAN_INSTRUCTIONS, ROOM_PHOTO_INSTRUCTIONS, visionMessages } from "./prompt.ts";
import { PLAN_SCHEMA, ROOM_PHOTO_SCHEMA } from "./schema.ts";
import {
  InvalidOutput,
  type PlanReading,
  type RoomPhotoAnalysis,
  validatePlanReading,
  validateRoomAnalysis,
} from "./validate.ts";

export interface VisionDeps {
  db: VisionDb | null;
  openrouter: OpenRouterClient;
  models: VisionModels;
  now?: () => Date;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Version of the consent screen of the app the seller accepted: the
 * images are only sent to a model with it (`consent` of the body). */
export const CONSENT_VERSION = "photo_analysis_v1";

/** The id [key] of the JSON body, or an error response; 403 without the
 * seller's consent to the vision AI. */
async function bodyId(request: Request, key: string): Promise<string | Response> {
  const body = await readCapped(request, VISION_LIMITS.bodyBytes);
  if (!body) return failure("too_long", 413);
  let parsed: Record<string, unknown> | null;
  try {
    const value = JSON.parse(new TextDecoder().decode(body));
    parsed = isRecord(value) ? value : null;
  } catch {
    return failure("bad_request", 400);
  }
  const value = parsed?.[key];
  if (typeof value !== "string" || !UUID.test(value)) return failure("bad_request", 400);
  if (parsed?.consent !== CONSENT_VERSION) return failure("consent_required", 403);
  return value;
}

/** The MIME type of a JPEG or PNG image (magic bytes), else null. */
export function imageType(bytes: Uint8Array): "image/jpeg" | "image/png" | null {
  if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (
    bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
    bytes[3] === 0x47
  ) {
    return "image/png";
  }
  return null;
}

interface Analysis<T> {
  kind: VisionKind;
  propertyId: string;
  targetId: string;
  path: string;
  model: string;
  instructions: string;
  schema: { name: string; schema: Record<string, unknown> };
  maxTokens: number;
  validate: (content: string, model: string, now: Date) => T;
  save: (result: T) => Promise<void>;
}

/** Downloads the image, calls the model (one retry on an unusable answer),
 * validates and stores the result; journals the cost. */
async function analyze<T>(
  deps: VisionDeps,
  db: VisionDb,
  now: Date,
  job: Analysis<T>,
): Promise<T | Response> {
  const requestId = await db.reserve(job.kind, job.propertyId, job.targetId, startOfDay(now));
  if (!requestId) return failure("quota", 429);
  const file: Download = await db.download(job.path, VISION_LIMITS.imageBytes);
  if (file === "missing") {
    await db.finish(requestId, { error: "missing_file" });
    return failure("not_found", 404);
  }
  if (file === "too_large") {
    await db.finish(requestId, { error: "too_large" });
    return failure("too_long", 413);
  }
  const type = imageType(file);
  if (!type) {
    await db.finish(requestId, { error: "unsupported" });
    return failure("unsupported", 415);
  }
  const messages = visionMessages(
    job.instructions,
    `data:${type};base64,${toBase64(file)}`,
  );
  let tokensIn = 0;
  let tokensOut = 0;
  let cost = 0;
  let ms = 0;
  const usage = () => ({
    model: job.model,
    tokens_in: tokensIn,
    tokens_out: tokensOut,
    cost_usd: cost,
    ms,
  });
  try {
    for (let attempt = 0;; attempt++) {
      const answer = await deps.openrouter.chat({
        model: job.model,
        messages,
        jsonSchema: job.schema,
        maxTokens: job.maxTokens,
        temperature: 0,
        provider: VISION_PROVIDER,
      });
      tokensIn += answer.usage.promptTokens ?? 0;
      tokensOut += answer.usage.completionTokens ?? 0;
      cost += answer.usage.cost ?? 0;
      ms += answer.ms;
      try {
        const result = job.validate(answer.content, job.model, now);
        await job.save(result);
        await db.finish(requestId, { ...usage(), error: null });
        return result;
      } catch (error) {
        if (!(error instanceof InvalidOutput) || attempt > 0) throw error;
      }
    }
  } catch (error) {
    const code = error instanceof InvalidOutput
      ? "invalid_output"
      : error instanceof OpenRouterError
      ? "upstream"
      : "failed";
    // Never echo upstream bodies to the app; logged server-side only.
    console.error(`${job.kind}: ${code}: ${error instanceof Error ? error.message : ""}`);
    await db.finish(requestId, { ...usage(), error: code }).catch(() => {});
    return failure(code === "invalid_output" ? "invalid_output" : "upstream", 502);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function handleVisionRoom(request: Request, deps: VisionDeps): Promise<Response> {
  if (request.method !== "POST") return failure("method", 405);
  const db = deps.db;
  if (!db) return failure("unauthorized", 401);
  const id = await bodyId(request, "photo_id");
  if (id instanceof Response) return id;
  try {
    const photo = await db.photo(id);
    if (!photo) return failure("not_found", 404);
    if (photo.property_status !== "draft") return failure("locked", 409);
    if (isRecord(photo.analysis) && photo.analysis.version === 1) {
      return json({ analysis: photo.analysis, cached: true });
    }
    const result = await analyze<RoomPhotoAnalysis>(deps, db, deps.now?.() ?? new Date(), {
      kind: "room_photo",
      propertyId: photo.property_id,
      targetId: photo.id,
      path: photo.storage_path,
      model: deps.models.room,
      instructions: ROOM_PHOTO_INSTRUCTIONS,
      schema: ROOM_PHOTO_SCHEMA,
      maxTokens: VISION_LIMITS.roomMaxTokens,
      validate: validateRoomAnalysis,
      save: (analysis) => db.saveAnalysis(photo, analysis),
    });
    if (result instanceof Response) return result;
    return json({ analysis: result, cached: false });
  } catch (error) {
    console.error(`vision-room: ${error instanceof Error ? error.message : "error"}`);
    return failure("upstream", 500);
  }
}

const PLAN_TYPES = ["image/jpeg", "image/png"];

export async function handlePlanReader(request: Request, deps: VisionDeps): Promise<Response> {
  if (request.method !== "POST") return failure("method", 405);
  const db = deps.db;
  if (!db) return failure("unauthorized", 401);
  const id = await bodyId(request, "document_id");
  if (id instanceof Response) return id;
  try {
    const document = await db.document(id);
    if (!document) return failure("not_found", 404);
    if (document.property_status !== "draft") return failure("locked", 409);
    if (document.kind !== "plan") return failure("bad_request", 400);
    if (!PLAN_TYPES.includes(document.mime_type ?? "")) return failure("unsupported", 415);
    const stored = isRecord(document.extracted) ? document.extracted.plan_reading : null;
    if (isRecord(stored) && stored.version === 1) {
      return json({ reading: stored, cached: true });
    }
    const result = await analyze<PlanReading>(deps, db, deps.now?.() ?? new Date(), {
      kind: "plan",
      propertyId: document.property_id,
      targetId: document.id,
      path: document.storage_path,
      model: deps.models.plan,
      instructions: PLAN_INSTRUCTIONS,
      schema: PLAN_SCHEMA,
      maxTokens: VISION_LIMITS.planMaxTokens,
      validate: validatePlanReading,
      save: (reading) => db.saveReading(document, reading),
    });
    if (result instanceof Response) return result;
    return json({ reading: result, cached: false });
  } catch (error) {
    console.error(`plan-reader: ${error instanceof Error ? error.message : "error"}`);
    return failure("upstream", 500);
  }
}
