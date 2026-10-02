// Half-year curve of the median €/m² and projection of past sales to today
// (plan §3.4).
import type { DvfSale, SemesterPoint } from "./types.ts";
import { clamp, median, monthsBefore, monthsBetween } from "./stats.ts";

/** Number of half-years of the curve (5 years). */
export const CURVE_LENGTH = 10;
/** Minimum sales per half-year for a commune-level curve. */
export const MIN_SALES_PER_SEMESTER = 8;
/** Cap of the yearly extrapolation beyond the last known sale. */
export const MAX_YEARLY_DRIFT = 0.05;

/** `2025-03-14` → `2025-S1`. */
export function semesterOf(date: string): string {
  const month = Number(date.slice(5, 7));
  return `${date.slice(0, 4)}-S${month <= 6 ? 1 : 2}`;
}

/** The [count] half-years ending with [last], oldest first. */
export function semestersEndingAt(last: string, count: number): string[] {
  let year = Number(last.slice(0, 4));
  let half = Number(last.slice(6));
  const result: string[] = [];
  for (let i = 0; i < count; i++) {
    result.unshift(`${year}-S${half}`);
    if (half === 2) {
      half = 1;
    } else {
      half = 2;
      year--;
    }
  }
  return result;
}

/** Rolling median of 3 half-years (2 at the edges). */
function smooth(points: Omit<SemesterPoint, "indexM2">[]): SemesterPoint[] {
  return points.map((point, i) => {
    const window = points.slice(Math.max(0, i - 1), i + 2).map((p) => p.medianM2);
    return { ...point, indexM2: Math.round(median(window)) };
  });
}

/**
 * Commune curve from the cleaned sales of the property type, or null when a
 * half-year has fewer than [MIN_SALES_PER_SEMESTER] sales.
 */
export function curveFromSales(
  sales: DvfSale[],
  dataUntil: string,
): SemesterPoint[] | null {
  const semesters = semestersEndingAt(semesterOf(dataUntil), CURVE_LENGTH);
  const bySemester = new Map<string, number[]>(semesters.map((s) => [s, []]));
  for (const sale of sales) {
    bySemester.get(semesterOf(sale.soldOn))?.push(sale.priceEur / sale.areaM2);
  }
  const points = [];
  for (const semester of semesters) {
    const values = bySemester.get(semester)!;
    if (values.length < MIN_SALES_PER_SEMESTER) return null;
    points.push({
      semester,
      medianM2: Math.round(median(values)),
      count: values.length,
      scale: "commune" as const,
    });
  }
  return smooth(points);
}

/** One month of the « Statistiques DVF » dataset. */
export interface MonthlyStat {
  /** `YYYY-MM`. */
  month: string;
  count: number;
  medianM2: number;
}

/**
 * Curve from monthly statistics (EPCI or département): monthly medians
 * averaged per half-year, weighted by their number of sales. Null when a
 * half-year has no sale.
 */
export function curveFromMonthly(
  stats: MonthlyStat[],
  dataUntil: string,
  scale: "epci" | "departement",
): SemesterPoint[] | null {
  const semesters = semestersEndingAt(semesterOf(dataUntil), CURVE_LENGTH);
  const sums = new Map(semesters.map((s) => [s, { weighted: 0, count: 0 }]));
  for (const stat of stats) {
    if (stat.count <= 0 || !(stat.medianM2 > 0)) continue;
    const sum = sums.get(semesterOf(`${stat.month}-01`));
    if (!sum) continue;
    sum.weighted += stat.medianM2 * stat.count;
    sum.count += stat.count;
  }
  const points = [];
  for (const semester of semesters) {
    const sum = sums.get(semester)!;
    if (sum.count === 0) return null;
    points.push({
      semester,
      medianM2: Math.round(sum.weighted / sum.count),
      count: sum.count,
      scale,
    });
  }
  return smooth(points);
}

function indexAt(curve: SemesterPoint[], semester: string): number {
  if (semester <= curve[0].semester) return curve[0].indexM2;
  for (const point of curve) if (point.semester === semester) return point.indexM2;
  return curve[curve.length - 1].indexM2;
}

/**
 * Yearly change (%) of the median €/m²: last 12 months of data vs the 12
 * before, from the sales when both windows have enough of them, else from
 * the curve (last two half-years vs the two before). Null when unknown.
 */
export function yearOnYearPct(
  sales: DvfSale[],
  dataUntil: string,
  curve: SemesterPoint[] | null,
): number | null {
  const yearAgo = monthsBefore(dataUntil, 12);
  const twoYearsAgo = monthsBefore(dataUntil, 24);
  const recent: number[] = [];
  const previous: number[] = [];
  for (const sale of sales) {
    const value = sale.priceEur / sale.areaM2;
    if (sale.soldOn > yearAgo && sale.soldOn <= dataUntil) recent.push(value);
    else if (sale.soldOn > twoYearsAgo && sale.soldOn <= yearAgo) previous.push(value);
  }
  let ratio: number | null = null;
  if (recent.length >= MIN_SALES_PER_SEMESTER && previous.length >= MIN_SALES_PER_SEMESTER) {
    ratio = median(recent) / median(previous);
  } else if (curve && curve.length >= 4) {
    const mean = (points: SemesterPoint[]) =>
      points.reduce((sum, p) => sum + p.medianM2 * p.count, 0) /
      points.reduce((sum, p) => sum + p.count, 0);
    ratio = mean(curve.slice(-2)) / mean(curve.slice(-4, -2));
  }
  return ratio === null ? null : Math.round((ratio - 1) * 1000) / 10;
}

/**
 * Factor bringing a sale of [soldOn] to [today]: curve index of the last
 * half-year / index of the sale's half-year, then the yearly change
 * (capped at ±5 %/year) from the last known sale to today.
 */
export function projectionFactor(
  curve: SemesterPoint[] | null,
  soldOn: string,
  dataUntil: string,
  today: string,
  yoyPct: number | null,
): number {
  const index = curve
    ? indexAt(curve, semesterOf(dataUntil)) / indexAt(curve, semesterOf(soldOn))
    : 1;
  const drift = clamp((yoyPct ?? 0) / 100, -MAX_YEARLY_DRIFT, MAX_YEARLY_DRIFT);
  const years = Math.max(0, monthsBetween(dataUntil, today) / 12);
  return index * Math.pow(1 + drift, years);
}
