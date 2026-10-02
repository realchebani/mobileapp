// HTTP handler of `estimate-property` (plan §2). Dependencies are injected
// so that the flow is tested without network nor database.
//
// POST {property_id}: the dossier is read with the caller's JWT (row level
// security: only its owner gets it). The estimate is computed once: an
// existing final result (ok / insufficient) is returned as is; otherwise a
// `running` snapshot is created and the computation continues in the
// background (202), the app then reads `market_snapshots`.
import { computeEstimate, insufficient } from "../_shared/estimation/estimate.ts";
import { type Explanation, frenchNumber } from "../_shared/estimation/explain.ts";
import {
  computeOutbuildingEstimate,
  outbuildingExplanation,
} from "../_shared/estimation/outbuilding.ts";
import {
  type EstimateResult,
  METHOD_VERSION,
  OUTBUILDING_METHOD_VERSION,
  type OutbuildingSubject,
  type Subject,
} from "../_shared/estimation/types.ts";
import type { MarketData, OutbuildingMarket } from "./market.ts";
import { type Dossier, hasRequiredDocuments, toSubject } from "./subject.ts";

/** New computations allowed per user over [ATTEMPTS_WINDOW_MS] (cost cap). */
export const MAX_ATTEMPTS_PER_DAY = 3;
export const ATTEMPTS_WINDOW_MS = 24 * 60 * 60 * 1000;

/** A `running` snapshot older than this is considered dead (CPU limit…). */
export const STALE_RUNNING_MS = 150_000;

// deno-lint-ignore no-explicit-any
export type SnapshotRow = Record<string, any>;

export interface Deps {
  loadDossier(propertyId: string): Promise<Dossier | null>;
  findFinal(propertyId: string): Promise<SnapshotRow | null>;
  findRunning(propertyId: string): Promise<{ id: string; created_at: string } | null>;
  /** Snapshots created since [since] for the properties of [ownerId]. */
  countRecentAttempts(ownerId: string, since: string): Promise<number>;
  /** Marks a `running` snapshot as dead (only while it is still running). */
  markStale(id: string): Promise<void>;
  /** Inserts a `running` snapshot; null when another one is running. */
  startSnapshot(propertyId: string, row: SnapshotRow): Promise<string | null>;
  updateSnapshot(id: string, row: SnapshotRow): Promise<void>;
  savePropertyEstimate(propertyId: string, values: SnapshotRow): Promise<void>;
  loadMarket(subject: Subject): Promise<MarketData>;
  loadOutbuildingMarket(subject: OutbuildingSubject): Promise<OutbuildingMarket>;
  explain(subject: Subject, result: EstimateResult): Promise<Explanation>;
  /** Keeps the work alive after the response (EdgeRuntime.waitUntil). */
  background(work: Promise<void>): void;
  now(): Date;
  log(message: string): void;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Columns of a finished snapshot. */
export function snapshotColumns(
  result: EstimateResult,
  subject: Subject | OutbuildingSubject | null,
  explanation: Explanation | null,
  sourceVersion: string | null,
  computedAt: string,
): SnapshotRow {
  return {
    status: result.status,
    reason: result.reason,
    computed_at: computedAt,
    method_version: subject?.type === "dependance" ? OUTBUILDING_METHOD_VERSION : METHOD_VERSION,
    source_version: sourceVersion,
    data_until: result.dataUntil,
    property_type: subject?.type ?? null,
    living_area_m2: subject?.type === "dependance" ? null : subject?.livingAreaM2 ?? null,
    city: subject?.city?.slice(0, 100) ?? null,
    estimate_low_eur: result.lowEur,
    estimate_median_eur: result.medianEur,
    estimate_high_eur: result.highEur,
    price_m2_low: result.priceM2Low,
    price_m2_median: result.priceM2Median,
    price_m2_high: result.priceM2High,
    confidence: result.confidence,
    comparables_count: result.comparablesCount,
    scope: result.scope,
    radius_m: result.radiusM,
    months: result.months,
    sales_12m: result.sales12m,
    yoy_change_pct: result.yoyChangePct,
    semester_medians: result.semesterMedians.map((p) => ({
      semester: p.semester,
      median_m2: p.medianM2,
      index_m2: p.indexM2,
      count: p.count,
      scale: p.scale,
    })),
    comparables: result.comparables,
    factors: result.factors,
    explanation_fr: explanation?.text.slice(0, 1000) ?? null,
    explanation_source: explanation?.source ?? null,
    error: explanation?.fallbackReason
      ? `explanation: ${explanation.fallbackReason}`.slice(0, 500)
      : null,
  };
}

/** The computation itself, run in the background. */
export async function compute(
  deps: Deps,
  snapshotId: string,
  propertyId: string,
  dossier: Dossier,
): Promise<void> {
  const computedAt = deps.now().toISOString();
  try {
    const subject = toSubject(dossier);
    if (typeof subject === "string") {
      await deps.updateSnapshot(
        snapshotId,
        snapshotColumns(insufficient(subject), null, null, null, computedAt),
      );
      return;
    }
    let result: EstimateResult;
    let explanation: Explanation | null = null;
    let sourceVersion: string;
    if (subject.type === "dependance") {
      const market = await deps.loadOutbuildingMarket(subject);
      sourceVersion = market.sourceVersion;
      result = market.dataUntil === null
        ? insufficient("too_few_sales")
        : computeOutbuildingEstimate({
          subject,
          communeSales: market.communeSales,
          nearbySales: market.nearbySales,
          dataUntil: market.dataUntil,
          today: computedAt.slice(0, 10),
        });
      if (result.status === "ok") {
        explanation = {
          text: outbuildingExplanation(subject, result, frenchNumber),
          source: "template",
        };
      }
    } else {
      const market = await deps.loadMarket(subject);
      sourceVersion = market.sourceVersion;
      result = market.dataUntil === null ? insufficient("too_few_sales") : computeEstimate({
        subject,
        communeSales: market.communeSales,
        nearbySales: market.nearbySales,
        curve: market.curve,
        dataUntil: market.dataUntil,
        today: computedAt.slice(0, 10),
      });
      if (result.status === "ok") explanation = await deps.explain(subject, result);
    }
    await deps.updateSnapshot(
      snapshotId,
      snapshotColumns(result, subject, explanation, sourceVersion, computedAt),
    );
    if (result.status === "ok") {
      try {
        await deps.savePropertyEstimate(propertyId, {
          ai_estimate_low_eur: result.lowEur,
          ai_estimate_median_eur: result.medianEur,
          ai_estimate_high_eur: result.highEur,
          ai_estimate_confidence: result.confidence,
          ai_estimate_computed_at: computedAt,
        });
      } catch (error) {
        // The snapshot is the reference; the copy on properties is a convenience.
        deps.log(`estimate-property: properties copy failed: ${String(error)}`);
      }
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    deps.log(`estimate-property: ${message}`);
    await deps.updateSnapshot(snapshotId, { status: "error", error: message.slice(0, 500) })
      .catch((e) => deps.log(`estimate-property: cannot record the error: ${String(e)}`));
  }
}

export async function handle(request: Request, deps: Deps): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  let propertyId: unknown;
  try {
    propertyId = (await request.json())?.property_id;
  } catch {
    propertyId = null;
  }
  if (typeof propertyId !== "string" || !UUID.test(propertyId)) {
    return json(400, { error: "invalid_property_id" });
  }
  const dossier = await deps.loadDossier(propertyId);
  if (dossier === null) return json(404, { error: "not_found" });
  if (!["submitted", "in_review"].includes(dossier.property.status)) {
    return json(409, { error: "not_submitted" });
  }
  // A type the estimate does not cover (land, commercial premises…): the
  // expert values it. Answered at once, nothing stored nor counted in the
  // quota.
  if (toSubject(dossier) === "unsupported_type") {
    return json(200, { status: "insufficient", reason: "unsupported_type" });
  }
  const final = await deps.findFinal(propertyId);
  if (final !== null) return json(200, final);

  const running = await deps.findRunning(propertyId);
  if (running !== null) {
    const age = deps.now().getTime() - Date.parse(running.created_at);
    if (age < STALE_RUNNING_MS) return json(202, { status: "running" });
    await deps.markStale(running.id);
  }
  if (!hasRequiredDocuments(dossier)) return json(409, { error: "missing_documents" });
  const since = new Date(deps.now().getTime() - ATTEMPTS_WINDOW_MS).toISOString();
  const attempts = await deps.countRecentAttempts(dossier.property.owner_id, since);
  if (attempts >= MAX_ATTEMPTS_PER_DAY) return json(429, { error: "too_many_attempts" });
  const snapshotId = await deps.startSnapshot(propertyId, {
    property_id: propertyId,
    status: "running",
    method_version: METHOD_VERSION,
    computed_at: deps.now().toISOString(),
  });
  if (snapshotId === null) return json(202, { status: "running" });
  deps.background(compute(deps, snapshotId, propertyId, dossier));
  return json(202, { status: "running" });
}
