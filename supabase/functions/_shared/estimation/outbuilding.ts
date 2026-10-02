// Non-certified estimate of a garage / parking or an outbuilding (EPIC-13,
// owner decision Q5): weighted median price of the DVF sales of one
// outbuilding alone ("Dépendance", no dwelling) around the property, with
// the same widening as the dwellings (radius first, then period) and no
// estimate under 5 comparables. Priced per unit: no surface, no €/m² trend.
import {
  displayDistance,
  insufficient,
  MAX_COMPARABLES_STORED,
  MIN_COMPARABLES,
  MIN_SALES_PER_STREET,
  RADIUS_FACTOR,
  TARGET_COMPARABLES,
  TIERS,
  WINDOW_FACTOR,
} from "./estimate.ts";
import {
  clamp,
  distanceM,
  effectiveCount,
  median,
  monthsBefore,
  monthsBetween,
  roundTo,
  weightedQuantile,
} from "./stats.ts";
import type { Comparable, EstimateResult, OutbuildingSale, OutbuildingSubject } from "./types.ts";

/** Prices are rounded to this step (€). */
export const OUTBUILDING_ROUNDING = 500;

export interface OutbuildingInput {
  subject: OutbuildingSubject;
  /** Outbuilding sales of the subject's commune (5 years). */
  communeSales: OutbuildingSale[];
  /** Outbuilding sales near it (up to the widest radius, any commune). */
  nearbySales: OutbuildingSale[];
  /** Date of the most recent known sale (`YYYY-MM-DD`). */
  dataUntil: string;
  /** Computation date (`YYYY-MM-DD`). */
  today: string;
}

/** Candidates of [sales] around [subject] in a radius and a period. */
export function countOutbuildingCandidates(
  subject: OutbuildingSubject,
  sales: OutbuildingSale[],
  dataUntil: string,
  radiusM: number,
  months: number,
): number {
  const since = monthsBefore(dataUntil, months);
  const seen = new Set<string>();
  for (const sale of sales) {
    if (
      sale.soldOn > since && sale.lat !== null && sale.lng !== null &&
      distanceM(subject.lat, subject.lng, sale.lat, sale.lng) <= radiusM
    ) {
      seen.add(`${sale.insee}|${sale.idMutation}`);
    }
  }
  return seen.size;
}

/** Most recent sale date of [sales], or null when there is none. */
export function latestOutbuildingSale(sales: OutbuildingSale[]): string | null {
  let latest: string | null = null;
  for (const sale of sales) if (latest === null || sale.soldOn > latest) latest = sale.soldOn;
  return latest;
}

function roundPrice(value: number): number {
  return Math.max(OUTBUILDING_ROUNDING, roundTo(value, OUTBUILDING_ROUNDING));
}

export function computeOutbuildingEstimate(input: OutbuildingInput): EstimateResult {
  const { subject, dataUntil, today } = input;
  const seen = new Set<string>();
  const all: OutbuildingSale[] = [];
  for (const sale of [...input.communeSales, ...input.nearbySales]) {
    const key = `${sale.insee}|${sale.idMutation}`;
    if (seen.has(key)) continue;
    seen.add(key);
    all.push(sale);
  }
  const streetCounts = new Map<string, number>();
  for (const sale of all) {
    if (sale.street === null) continue;
    const key = `${sale.insee}|${sale.street}`;
    streetCounts.set(key, (streetCounts.get(key) ?? 0) + 1);
  }
  const located = all
    .filter((sale) => sale.lat !== null && sale.lng !== null)
    .map((sale) => ({ sale, distance: distanceM(subject.lat, subject.lng, sale.lat!, sale.lng!) }));

  const inTier = (tier: (typeof TIERS)[number]) => {
    const since = monthsBefore(dataUntil, tier.months);
    return located.filter((c) => c.sale.soldOn > since && c.distance <= tier.radiusM);
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

  const common = {
    dataUntil,
    sales12m: input.communeSales.filter((s) => s.soldOn > monthsBefore(dataUntil, 12)).length,
  };
  if (selected.length < MIN_COMPARABLES) {
    return insufficient("too_few_sales", { ...common, comparablesCount: selected.length });
  }

  const weights = selected.map((c) =>
    (1 / (1 + c.distance / 500)) *
    Math.pow(0.5, Math.max(0, monthsBetween(c.sale.soldOn, today)) / 24)
  );
  const prices = selected.map((c) => c.sale.priceEur);
  const low = weightedQuantile(prices, weights, 0.25);
  const mid = weightedQuantile(prices, weights, 0.5);
  const high = weightedQuantile(prices, weights, 0.75);

  // Confidence (0–100): same factors as the dwellings, without the data
  // completeness (nothing to declare for an outbuilding).
  const fN = Math.min(1, effectiveCount(weights) / 20);
  const fDispersion = clamp(1 - ((high - low) / mid - 0.15) / 0.35, 0, 1);
  const medianAge = median(selected.map((c) => monthsBetween(c.sale.soldOn, today)));
  const fRecency = clamp(1 - (medianAge - 6) / 30, 0, 1) * WINDOW_FACTOR[tier.months];
  const confidence = Math.round(
    100 * (0.4 * fN + 0.25 * fDispersion + 0.2 * RADIUS_FACTOR[tier.radiusM] + 0.15 * fRecency),
  );

  const comparables: Comparable[] = selected
    .map((c, i) => ({ c, weight: weights[i] }))
    .sort((a, b) => b.weight - a.weight || b.c.sale.soldOn.localeCompare(a.c.sale.soldOn))
    .slice(0, MAX_COMPARABLES_STORED)
    .map(({ c, weight }) => {
      const street = c.sale.street;
      const streetCount = street === null ? 0 : streetCounts.get(`${c.sale.insee}|${street}`) ?? 0;
      return {
        type: "dependance",
        street: streetCount >= MIN_SALES_PER_STREET ? street : null,
        area_m2: null,
        rooms: null,
        land_m2: null,
        sold_year: Number(c.sale.soldOn.slice(0, 4)),
        distance_m: displayDistance(c.distance),
        price_eur: c.sale.priceEur,
        price_m2_eur: null,
        price_m2_today_eur: null,
        weight: Math.round(weight * 1000) / 1000,
      };
    });

  const medianEur = roundPrice(mid);
  return {
    ...common,
    status: "ok",
    reason: null,
    lowEur: Math.min(roundPrice(low), medianEur),
    medianEur,
    highEur: Math.max(roundPrice(high), medianEur),
    priceM2Low: null,
    priceM2Median: null,
    priceM2High: null,
    confidence,
    comparablesCount: selected.length,
    scope: "radius",
    radiusM: tier.radiusM,
    months: tier.months,
    yoyChangePct: null,
    semesterMedians: [],
    comparables,
    factors: [],
  };
}

/** Deterministic French explanation (no AI: the figures are few and
 * simple, and nothing may be invented). */
export function outbuildingExplanation(
  subject: OutbuildingSubject,
  result: EstimateResult,
  frenchNumber: (value: number) => string,
): string {
  const radius = result.radiusM === null
    ? "dans votre secteur"
    : `à moins de ${
      result.radiusM < 1000 ? `${result.radiusM} m` : `${result.radiusM / 1000} km`
    } de votre bien`;
  const period = result.months === null
    ? ""
    : ` sur les ${Math.round(result.months / 12)} dernières années`;
  const what = subject.kind === "stationnement"
    ? "garages, parkings et box vendus seuls"
    : "dépendances vendues seules (caves, garages, remises…)";
  return `D’après ${result.comparablesCount} ventes de ${what} ${radius}${period}, ` +
    `le prix médian ressort à ${frenchNumber(result.medianEur ?? 0)} €, ` +
    `soit une tendance de ${frenchNumber(result.lowEur ?? 0)} à ` +
    `${frenchNumber(result.highEur ?? 0)} €. ` +
    "Ces chiffres sont indicatifs et non certifiés : votre expert établira la valeur de votre bien.";
}
