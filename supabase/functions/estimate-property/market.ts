// Loads the market data of a subject: DVF sales of its commune (5 years),
// then of the communes around it, ring after ring (2 → 5 → 10 → 20 km, the
// 3 most recent years) until there are enough recent comparables, then 5
// years only if the widest ring is still too sparse (freshness first,
// owner decision 2026-10-02); and the half-year curve (commune, else EPCI,
// else département statistics).
import {
  type CommuneCentre,
  communesWithin,
  type FetchLike,
  monthlyStats,
} from "../_shared/dvf/sources.ts";
import {
  AREA_TOLERANCE,
  countCandidates,
  latestSaleDate,
  RADII_M,
  TARGET_COMPARABLES,
  WINDOWS_MONTHS,
} from "../_shared/estimation/estimate.ts";
import { monthsBefore } from "../_shared/estimation/stats.ts";
import { curveFromMonthly, curveFromSales } from "../_shared/estimation/trend.ts";
import {
  countOutbuildingCandidates,
  latestOutbuildingSale,
} from "../_shared/estimation/outbuilding.ts";
import type {
  DvfSale,
  OutbuildingSale,
  OutbuildingSubject,
  PropertyType,
  SemesterPoint,
  Subject,
} from "../_shared/estimation/types.ts";

export interface SalesStore {
  ensureLoaded(insees: string[], years: number[]): Promise<string | null>;
  communeSales(insee: string, type: PropertyType): Promise<DvfSale[]>;
  nearbySales(options: {
    insees: string[];
    type: PropertyType;
    box: { minLat: number; maxLat: number; minLng: number; maxLng: number };
    minArea: number;
    maxArea: number;
    since: string;
  }): Promise<DvfSale[]>;
}

export interface MarketData {
  communeSales: DvfSale[];
  nearbySales: DvfSale[];
  curve: SemesterPoint[] | null;
  dataUntil: string | null;
  sourceVersion: string;
}

function years(from: number, to: number): number[] {
  const result: number[] = [];
  for (let year = to; year >= from; year--) result.push(year);
  return result;
}

/** Curve from the monthly statistics of the EPCI, then the département. */
async function statisticsCurve(
  fetcher: FetchLike,
  subject: Subject,
  dataUntil: string,
): Promise<SemesterPoint[] | null> {
  try {
    const commune = await monthlyStats(fetcher, subject.insee, subject.type);
    if (commune.parent) {
      const epci = await monthlyStats(fetcher, commune.parent, subject.type);
      const curve = curveFromMonthly(epci.stats, dataUntil, "epci");
      if (curve) return curve;
      if (epci.parent && epci.parent !== "nation") {
        const department = await monthlyStats(fetcher, epci.parent, subject.type);
        return curveFromMonthly(department.stats, dataUntil, "departement");
      }
    }
  } catch {
    // The statistics are optional: no curve means no projection.
  }
  return null;
}

/** Rings loaded progressively (the smaller radii are inside the first one). */
const LOAD_RADII_M = RADII_M.filter((radius) => radius >= 2000);
/** Wall-clock budget for loading (Edge Function limit ~150 s): the cache keeps
 * what was loaded, a retry resumes from there. */
export const LOAD_BUDGET_MS = 100_000;

export async function loadMarket(
  subject: Subject,
  store: SalesStore,
  fetcher: FetchLike,
  today: Date,
  clock: () => number = Date.now,
): Promise<MarketData> {
  const deadline = clock() + LOAD_BUDGET_MS;
  const checkBudget = () => {
    if (clock() > deadline) throw new Error("load budget exceeded (cache kept, retry resumes)");
  };
  const year = today.getUTCFullYear();
  // geo-dvf keeps 5 vintages; the current year is probed (404 until published).
  const sourceDate = await store.ensureLoaded([subject.insee], years(year - 5, year));
  const communeSales = await store.communeSales(subject.insee, subject.type);
  const latest = latestSaleDate(communeSales);
  const lastYear = latest ? Number(latest.slice(0, 4)) : year - 1;

  const loaded = new Set([subject.insee]);
  const departments = new Map<string, CommuneCentre[]>();
  let neighbourDate: string | null = null;
  let nearbySales: DvfSale[] = [];
  const query = (radius: number) => {
    const reach = radius * 1.05;
    const dLat = reach / 111320;
    const dLng = reach / (111320 * Math.cos((subject.lat * Math.PI) / 180));
    return store.nearbySales({
      insees: [...loaded],
      type: subject.type,
      box: {
        minLat: subject.lat - dLat,
        maxLat: subject.lat + dLat,
        minLng: subject.lng - dLng,
        maxLng: subject.lng + dLng,
      },
      minArea: subject.livingAreaM2 * (1 - AREA_TOLERANCE),
      maxArea: subject.livingAreaM2 * (1 + AREA_TOLERANCE),
      since: monthsBefore(`${lastYear}-12-31`, 72),
    });
  };
  const enough = (radius: number, months: number) => {
    const all = [...communeSales, ...nearbySales];
    const until = latestSaleDate(all);
    return until !== null &&
      countCandidates(subject, all, until, radius, months) >= TARGET_COMPARABLES;
  };

  // Geography first, on the most recent years.
  let radius = LOAD_RADII_M[0];
  for (radius of LOAD_RADII_M) {
    checkBudget();
    const codes = await communesWithin(fetcher, subject.lat, subject.lng, radius, departments);
    const fresh = codes.filter((code) => !loaded.has(code));
    if (fresh.length > 0) {
      neighbourDate = await store.ensureLoaded(fresh, years(lastYear - 2, lastYear)) ??
        neighbourDate;
      for (const code of fresh) loaded.add(code);
    }
    nearbySales = await query(radius);
    if (enough(radius, WINDOWS_MONTHS[0])) break;
  }
  // Older years only when even the widest ring lacks recent sales.
  if (!enough(radius, WINDOWS_MONTHS[1])) {
    checkBudget();
    const others = [...loaded].filter((code) => code !== subject.insee);
    if (others.length > 0) await store.ensureLoaded(others, years(lastYear - 5, lastYear - 3));
    nearbySales = await query(radius);
  }

  const dataUntil = latestSaleDate([...communeSales, ...nearbySales]);
  const curve = dataUntil === null ? null : curveFromSales(communeSales, dataUntil) ??
    await statisticsCurve(fetcher, subject, dataUntil);
  const published = sourceDate ?? neighbourDate;
  const sourceVersion = [
    "geo-dvf",
    published ? new Date(published).toISOString().slice(0, 10) : null,
    curve && curve[0].scale !== "commune" ? `stats DVF ${curve[0].scale}` : null,
  ].filter(Boolean).join(" ");
  return { communeSales, nearbySales, curve, dataUntil, sourceVersion };
}

// ---------------------------------------------------------------------------
// Outbuildings (garages, parkings, caves… EPIC-13): sales of one outbuilding
// alone, same widening (rings on the 3 recent years, then 5 years), no
// surface filter and no curve (priced per unit).
// ---------------------------------------------------------------------------

export interface OutbuildingStore {
  ensureLoaded(insees: string[], years: number[]): Promise<string | null>;
  communeOutbuildingSales(insee: string): Promise<OutbuildingSale[]>;
  nearbyOutbuildingSales(options: {
    insees: string[];
    box: { minLat: number; maxLat: number; minLng: number; maxLng: number };
    since: string;
  }): Promise<OutbuildingSale[]>;
}

export interface OutbuildingMarket {
  communeSales: OutbuildingSale[];
  nearbySales: OutbuildingSale[];
  dataUntil: string | null;
  sourceVersion: string;
}

export async function loadOutbuildingMarket(
  subject: OutbuildingSubject,
  store: OutbuildingStore,
  fetcher: FetchLike,
  today: Date,
  clock: () => number = Date.now,
): Promise<OutbuildingMarket> {
  const deadline = clock() + LOAD_BUDGET_MS;
  const checkBudget = () => {
    if (clock() > deadline) throw new Error("load budget exceeded (cache kept, retry resumes)");
  };
  const year = today.getUTCFullYear();
  const sourceDate = await store.ensureLoaded([subject.insee], years(year - 5, year));
  const communeSales = await store.communeOutbuildingSales(subject.insee);
  const latest = latestOutbuildingSale(communeSales);
  const lastYear = latest ? Number(latest.slice(0, 4)) : year - 1;

  const loaded = new Set([subject.insee]);
  const departments = new Map<string, CommuneCentre[]>();
  let neighbourDate: string | null = null;
  let nearbySales: OutbuildingSale[] = [];
  const query = (radius: number) => {
    const reach = radius * 1.05;
    const dLat = reach / 111320;
    const dLng = reach / (111320 * Math.cos((subject.lat * Math.PI) / 180));
    return store.nearbyOutbuildingSales({
      insees: [...loaded],
      box: {
        minLat: subject.lat - dLat,
        maxLat: subject.lat + dLat,
        minLng: subject.lng - dLng,
        maxLng: subject.lng + dLng,
      },
      since: monthsBefore(`${lastYear}-12-31`, 72),
    });
  };
  const enough = (radius: number, months: number) => {
    const all = [...communeSales, ...nearbySales];
    const until = latestOutbuildingSale(all);
    return until !== null &&
      countOutbuildingCandidates(subject, all, until, radius, months) >= TARGET_COMPARABLES;
  };

  let radius = LOAD_RADII_M[0];
  for (radius of LOAD_RADII_M) {
    checkBudget();
    const codes = await communesWithin(fetcher, subject.lat, subject.lng, radius, departments);
    const fresh = codes.filter((code) => !loaded.has(code));
    if (fresh.length > 0) {
      neighbourDate = await store.ensureLoaded(fresh, years(lastYear - 2, lastYear)) ??
        neighbourDate;
      for (const code of fresh) loaded.add(code);
    }
    nearbySales = await query(radius);
    if (enough(radius, WINDOWS_MONTHS[0])) break;
  }
  if (!enough(radius, WINDOWS_MONTHS[1])) {
    checkBudget();
    const others = [...loaded].filter((code) => code !== subject.insee);
    if (others.length > 0) await store.ensureLoaded(others, years(lastYear - 5, lastYear - 3));
    nearbySales = await query(radius);
  }

  const dataUntil = latestOutbuildingSale([...communeSales, ...nearbySales]);
  const published = sourceDate ?? neighbourDate;
  const sourceVersion = [
    "geo-dvf",
    published ? new Date(published).toISOString().slice(0, 10) : null,
  ]
    .filter(Boolean).join(" ");
  return { communeSales, nearbySales, dataUntil, sourceVersion };
}
