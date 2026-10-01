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

interface Tier {
  radiusM: number | null;
  months: number;
  distanceFactor: number;
}

const TIERS: Tier[] = [
  { radiusM: 500, months: 36, distanceFactor: 1 },
  { radiusM: 1000, months: 36, distanceFactor: 0.8 },
  { radiusM: 2000, months: 36, distanceFactor: 0.6 },
  { radiusM: null, months: 36, distanceFactor: 0.4 },
  { radiusM: null, months: 60, distanceFactor: 0.3 },
];

/** Distance assumed for a sale without coordinates (commune tiers). */
const UNKNOWN_DISTANCE_M = 2000;

export interface EstimateInput {
  subject: Subject;
  /** Sales of the subject's type in its commune (5 years). */
  communeSales: DvfSale[];
  /** Sales of the subject's type near it (≤ 2 km, any commune). */
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

/** Rounded display distance: 50 m steps under 1 km, then 100 m. */
export function displayDistance(distance: number | null): number | null {
  if (distance === null) return null;
  return distance < 1000 ? Math.max(50, roundTo(distance, 50)) : roundTo(distance, 100);
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
      c.sale.soldOn > since &&
      (tier.radiusM === null
        ? c.sale.insee === subject.insee
        : c.distance !== null && c.distance <= tier.radiusM)
    );
  };
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
    (1 / (1 + (c.distance ?? UNKNOWN_DISTANCE_M) / 500)) *
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
  const fRecency = clamp(1 - (medianAge - 6) / 30, 0, 1);
  const inputs = [true, subject.roomsCount !== null, subject.constructionYear !== null];
  if (subject.type === "maison") inputs.push(subject.landM2 !== null);
  const fData = inputs.filter(Boolean).length / inputs.length;
  const confidence = Math.round(
    100 *
      (0.35 * fN + 0.25 * fDispersion + 0.15 * tier.distanceFactor + 0.15 * fRecency +
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
        sold_on: c.sale.soldOn.slice(0, 7),
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
    scope: tier.radiusM === null ? "commune" : "radius",
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
