// Loads the market data of a subject: DVF sales of its commune (5 years)
// and of the communes up to 2 km around it, and the half-year curve
// (commune, else EPCI, else département statistics).
import { communesAround, type FetchLike, monthlyStats } from "../_shared/dvf/sources.ts";
import { AREA_TOLERANCE, latestSaleDate } from "../_shared/estimation/estimate.ts";
import { monthsBefore } from "../_shared/estimation/stats.ts";
import { curveFromMonthly, curveFromSales } from "../_shared/estimation/trend.ts";
import type { DvfSale, PropertyType, SemesterPoint, Subject } from "../_shared/estimation/types.ts";

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

/** Radius of the neighbourhood search, with a margin for the box. */
const NEARBY_RADIUS_M = 2100;

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

export async function loadMarket(
  subject: Subject,
  store: SalesStore,
  fetcher: FetchLike,
  today: Date,
): Promise<MarketData> {
  const year = today.getUTCFullYear();
  // geo-dvf keeps 5 vintages; the current year is probed (404 until published).
  const sourceDate = await store.ensureLoaded([subject.insee], years(year - 5, year));
  const communeSales = await store.communeSales(subject.insee, subject.type);

  const around = (await communesAround(fetcher, subject.lat, subject.lng))
    .filter((code) => code !== subject.insee);
  const latest = latestSaleDate(communeSales);
  const lastYear = latest ? Number(latest.slice(0, 4)) : year;
  let neighbourDate: string | null = null;
  if (around.length > 0) {
    neighbourDate = await store.ensureLoaded(around, years(lastYear - 3, lastYear));
  }
  const dLat = NEARBY_RADIUS_M / 111320;
  const dLng = NEARBY_RADIUS_M / (111320 * Math.cos((subject.lat * Math.PI) / 180));
  const nearbySales = await store.nearbySales({
    insees: [subject.insee, ...around],
    type: subject.type,
    box: {
      minLat: subject.lat - dLat,
      maxLat: subject.lat + dLat,
      minLng: subject.lng - dLng,
      maxLng: subject.lng + dLng,
    },
    minArea: subject.livingAreaM2 * (1 - AREA_TOLERANCE),
    maxArea: subject.livingAreaM2 * (1 + AREA_TOLERANCE),
    since: monthsBefore(`${lastYear}-12-31`, 48),
  });

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
