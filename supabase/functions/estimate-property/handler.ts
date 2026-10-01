// HTTP handler of `estimate-property` (plan §2). Dependencies are injected
// so that the flow is tested without network nor database.
//
// POST {property_id}: the dossier is read with the caller's JWT (row level
// security: only its owner gets it). The estimate is computed once: an
// existing final result (ok / insufficient) is returned as is; otherwise a
// `running` snapshot is created and the computation continues in the
// background (202), the app then reads `market_snapshots`.
import { computeEstimate, insufficient } from "../_shared/estimation/estimate.ts";
import type { Explanation } from "../_shared/estimation/explain.ts";
import { type EstimateResult, METHOD_VERSION, type Subject } from "../_shared/estimation/types.ts";
import type { MarketData } from "./market.ts";
import { type Dossier, toSubject } from "./subject.ts";

/** A `running` snapshot older than this is considered dead (CPU limit…). */
export const STALE_RUNNING_MS = 150_000;

// deno-lint-ignore no-explicit-any
export type SnapshotRow = Record<string, any>;

export interface Deps {
  loadDossier(propertyId: string): Promise<Dossier | null>;
  findFinal(propertyId: string): Promise<SnapshotRow | null>;
  findRunning(propertyId: string): Promise<{ id: string; created_at: string } | null>;
  /** Inserts a `running` snapshot; null when another one is running. */
  startSnapshot(propertyId: string, row: SnapshotRow): Promise<string | null>;
  updateSnapshot(id: string, row: SnapshotRow): Promise<void>;
  savePropertyEstimate(propertyId: string, values: SnapshotRow): Promise<void>;
  loadMarket(subject: Subject): Promise<MarketData>;
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
  subject: Subject | null,
  explanation: Explanation | null,
  sourceVersion: string | null,
  computedAt: string,
): SnapshotRow {
  return {
    status: result.status,
    reason: result.reason,
    computed_at: computedAt,
    method_version: METHOD_VERSION,
    source_version: sourceVersion,
    data_until: result.dataUntil,
    property_type: subject?.type ?? null,
    living_area_m2: subject?.livingAreaM2 ?? null,
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
    const market = await deps.loadMarket(subject);
    const result = market.dataUntil === null ? insufficient("too_few_sales") : computeEstimate({
      subject,
      communeSales: market.communeSales,
      nearbySales: market.nearbySales,
      curve: market.curve,
      dataUntil: market.dataUntil,
      today: computedAt.slice(0, 10),
    });
    const explanation = result.status === "ok" ? await deps.explain(subject, result) : null;
    await deps.updateSnapshot(
      snapshotId,
      snapshotColumns(result, subject, explanation, market.sourceVersion, computedAt),
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
  const final = await deps.findFinal(propertyId);
  if (final !== null) return json(200, final);

  const running = await deps.findRunning(propertyId);
  if (running !== null) {
    const age = deps.now().getTime() - Date.parse(running.created_at);
    if (age < STALE_RUNNING_MS) return json(202, { status: "running" });
    await deps.updateSnapshot(running.id, { status: "error", error: "stale" });
  }
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
