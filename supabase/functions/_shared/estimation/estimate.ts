// Deterministic non-certified estimate (plan §3, owner's arbitrations:
// no adjustment in v1 — sector €/m² × living area, range from the
// quartiles; no estimate under 5 comparables).
import type { Comparable, DvfSale, EstimateResult, SemesterPoint, Subject } from "./types.ts";
import {
  clamp,
  distanceM,
  effectiveCount,
  median,
  monthsBefore,
  monthsBetween,
  quantile,
  roundTo,
  weightedQuantile,
} from "./stats.ts";
import { projectionFactor, yearOnYearPct } from "./trend.ts";
import { buildFactors } from "./factors.ts";

/** Below this many comparables there is no estimate (« l’expert s’en charge »). */
export const MIN_COMPARABLES = 5;
/** A tier stops the widening once it has this many comparables. */
export const TARGET_COMPARABLES = 10;
/** Surface tolerance of the comparables (± 30 %). */
export const AREA_TOLERANCE = 0.3;
/** A street is shown only with at least this many sales in it. */
export const MIN_SALES_PER_STREET = 3;
/** Comparables kept in the snapshot. */
export const MAX_COMPARABLES_STORED = 30;

/** Search radii, widened until enough comparables (owner decision 2026-10-02). */
export const RADII_M = [500, 1000, 2000, 5000, 10000, 20000];
/** Time windows: the most recent first, widened only after the widest radius. */
export const WINDOWS_MONTHS = [24, 36, 60];

/** Confidence factor of each radius (proximity of the comparables). */
const RADIUS_FACTOR: Record<number, number> = {
  500: 1,
  1000: 0.85,
  2000: 0.7,
  5000: 0.5,
  10000: 0.35,
  20000: 0.2,
};
/** Confidence factor of each time window (freshness first). */
const WINDOW_FACTOR: Record<number, number> = { 24: 1, 36: 0.8, 60: 0.5 };

interface Tier {
  radiusM: number;
  months: number;
}

/** Recency first: every radius at 24 months, then at 36, then at 60. */
export const TIERS: Tier[] = WINDOWS_MONTHS.flatMap((months) =>
  RADII_M.map((radiusM) => ({ radiusM, months }))
);

/** Candidates of [sales] for [subject] in a radius and a period (no outlier filter). */
export function countCandidates(
  subject: Subject,
  sales: DvfSale[],
  dataUntil: string,
  radiusM: number,
  months: number,
): number {
  const since = monthsBefore(dataUntil, months);
  const seen = new Set<string>();
  for (const sale of sales) {
    if (
      sale.type === subject.type && sale.soldOn > since && sale.lat !== null &&
      sale.lng !== null &&
      Math.abs(sale.areaM2 - subject.livingAreaM2) <= AREA_TOLERANCE * subject.livingAreaM2 &&
      distanceM(subject.lat, subject.lng, sale.lat, sale.lng) <= radiusM
    ) {
      seen.add(`${sale.insee}|${sale.idMutation}`);
    }
  }
  return seen.size;
}

export interface EstimateInput {
  subject: Subject;
  /** Sales of the subject's type in its commune (5 years). */
  communeSales: DvfSale[];
  /** Sales of the subject's type near it (up to the widest radius, any commune). */
  nearbySales: DvfSale[];
  /** Half-year curve (commune, EPCI or département), null if unknown. */
  curve: SemesterPoint[] | null;
  /** Date of the most recent known sale (`YYYY-MM-DD`). */
  dataUntil: string;
  /** Computation date (`YYYY-MM-DD`). */
  today: string;
}

/** Most recent sale date of [sales], or null when there is none. */
export function latestSaleDate(sales: DvfSale[]): string | null {
  let latest: string | null = null;
  for (const sale of sales) if (latest === null || sale.soldOn > latest) latest = sale.soldOn;
  return latest;
}

interface Candidate {
  sale: DvfSale;
  distance: number | null;
  priceM2Today: number;
}

/** Rounded display distance: 100 m steps (at least 100 m), for discretion. */
export function displayDistance(distance: number | null): number | null {
  if (distance === null) return null;
  return Math.max(100, roundTo(distance, 100));
}

export function insufficient(
  reason: EstimateResult["reason"],
  extra: Partial<EstimateResult> = {},
): EstimateResult {
  return {
    status: "insufficient",
    reason,
    dataUntil: null,
    lowEur: null,
    medianEur: null,
    highEur: null,
    priceM2Low: null,
    priceM2Median: null,
    priceM2High: null,
    confidence: null,
    comparablesCount: 0,
    scope: null,
    radiusM: null,
    months: null,
    sales12m: null,
    yoyChangePct: null,
    semesterMedians: [],
    comparables: [],
    factors: [],
    ...extra,
  };
}

export function computeEstimate(input: EstimateInput): EstimateResult {
  const { subject, communeSales, curve, dataUntil, today } = input;
  const yoy = yearOnYearPct(communeSales, dataUntil, curve);
  const project = (sale: DvfSale) =>
    (sale.priceEur / sale.areaM2) *
    projectionFactor(curve, sale.soldOn, dataUntil, today, yoy);

  // Outliers: outside 1.5 × IQR of the commune's projected €/m².
  const communeM2 = communeSales.map(project);
  let bounds = { min: -Infinity, max: Infinity };
  if (communeM2.length >= 8) {
    const q1 = quantile(communeM2, 0.25);
    const q3 = quantile(communeM2, 0.75);
    bounds = { min: q1 - 1.5 * (q3 - q1), max: q3 + 1.5 * (q3 - q1) };
  }

  const seen = new Set<string>();
  const all: DvfSale[] = [];
  for (const sale of [...communeSales, ...input.nearbySales]) {
    const key = `${sale.insee}|${sale.idMutation}`;
    if (seen.has(key) || sale.type !== subject.type) continue;
    seen.add(key);
    all.push(sale);
  }
  const streetCounts = new Map<string, number>();
  for (const sale of all) {
    if (sale.street === null) continue;
    const key = `${sale.insee}|${sale.street}`;
    streetCounts.set(key, (streetCounts.get(key) ?? 0) + 1);
  }

  const area = subject.livingAreaM2;
  const candidates: Candidate[] = [];
  for (const sale of all) {
    if (Math.abs(sale.areaM2 - area) > AREA_TOLERANCE * area) continue;
    const priceM2Today = project(sale);
    if (priceM2Today < bounds.min || priceM2Today > bounds.max) continue;
    const distance = sale.lat === null || sale.lng === null
      ? null
      : distanceM(subject.lat, subject.lng, sale.lat, sale.lng);
    candidates.push({ sale, distance, priceM2Today });
  }

  const inTier = (tier: Tier) => {
    const since = monthsBefore(dataUntil, tier.months);
    return candidates.filter((c) =>
      c.sale.soldOn > since && c.distance !== null && c.distance <= tier.radiusM
    );
  };
  // First tier reaching the target; otherwise the one with the most
  // comparables (the earliest, i.e. freshest and closest, on ties).
  let tier = TIERS[0];
  let selected = inTier(tier);
  for (const next of TIERS.slice(1)) {
    if (selected.length >= TARGET_COMPARABLES) break;
    const widened = inTier(next);
    if (widened.length > selected.length) {
      tier = next;
      selected = widened;
    }
  }

  const sales12m = communeSales.filter((s) => s.soldOn > monthsBefore(dataUntil, 12)).length;
  const common = {
    dataUntil,
    sales12m,
    yoyChangePct: yoy,
    semesterMedians: curve ?? [],
  };
  if (selected.length < MIN_COMPARABLES) {
    return insufficient("too_few_sales", { ...common, comparablesCount: selected.length });
  }

  const weights = selected.map((c) =>
    (1 / (1 + c.distance! / 500)) *
    Math.pow(0.5, Math.max(0, monthsBetween(c.sale.soldOn, today)) / 24)
  );
  const values = selected.map((c) => c.priceM2Today);
  const m2Low = weightedQuantile(values, weights, 0.25);
  const m2Median = weightedQuantile(values, weights, 0.5);
  const m2High = weightedQuantile(values, weights, 0.75);

  // Confidence (0–100), plan §3.6.
  const fN = Math.min(1, effectiveCount(weights) / 20);
  const fDispersion = clamp(1 - ((m2High - m2Low) / m2Median - 0.15) / 0.35, 0, 1);
  const medianAge = median(selected.map((c) => monthsBetween(c.sale.soldOn, today)));
  const fRecency = clamp(1 - (medianAge - 6) / 30, 0, 1) * WINDOW_FACTOR[tier.months];
  const inputs = [true, subject.roomsCount !== null, subject.constructionYear !== null];
  if (subject.type === "maison") inputs.push(subject.landM2 !== null);
  const fData = inputs.filter(Boolean).length / inputs.length;
  const confidence = Math.round(
    100 *
      (0.35 * fN + 0.25 * fDispersion + 0.15 * RADIUS_FACTOR[tier.radiusM] + 0.15 * fRecency +
        0.1 * fData),
  );

  const medianEur = roundTo(m2Median * area, 1000);
  const widening = 1 + Math.max(0, 60 - confidence) / 100;
  const z = clamp(0.5 * Math.log(m2High / m2Low) * widening, Math.log(1.05), Math.log(1.2));

  const comparables: Comparable[] = selected
    .map((c, i) => ({ c, weight: weights[i] }))
    .sort((a, b) => b.weight - a.weight || b.c.sale.soldOn.localeCompare(a.c.sale.soldOn))
    .slice(0, MAX_COMPARABLES_STORED)
    .map(({ c, weight }) => {
      const street = c.sale.street;
      const streetCount = street === null ? 0 : streetCounts.get(`${c.sale.insee}|${street}`) ?? 0;
      return {
        type: c.sale.type,
        street: streetCount >= MIN_SALES_PER_STREET ? street : null,
        area_m2: Math.round(c.sale.areaM2),
        rooms: c.sale.rooms,
        land_m2: c.sale.landM2,
        sold_year: Number(c.sale.soldOn.slice(0, 4)),
        distance_m: displayDistance(c.distance),
        price_eur: c.sale.priceEur,
        price_m2_eur: Math.round(c.sale.priceEur / c.sale.areaM2),
        price_m2_today_eur: Math.round(c.priceM2Today),
        weight: Math.round(weight * 1000) / 1000,
      };
    });

  return {
    ...common,
    status: "ok",
    reason: null,
    lowEur: roundTo(medianEur * Math.exp(-z), 1000),
    medianEur,
    highEur: roundTo(medianEur * Math.exp(z), 1000),
    priceM2Low: Math.round(m2Low),
    priceM2Median: Math.round(m2Median),
    priceM2High: Math.round(m2High),
    confidence,
    comparablesCount: selected.length,
    scope: "radius",
    radiusM: tier.radiusM,
    months: tier.months,
    comparables,
    factors: buildFactors(
      subject,
      selected.map((c) => c.sale.landM2).filter((l): l is number => l !== null),
      Number(today.slice(0, 4)),
    ),
  };
}
