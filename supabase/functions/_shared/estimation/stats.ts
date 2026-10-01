// Small statistics helpers (deterministic, no dependency).

/** Median of [values] (mean of the two middle values when even); NaN if empty. */
export function median(values: number[]): number {
  return quantile(values, 0.5);
}

/** Quantile [q] ∈ [0, 1] with linear interpolation (type 7); NaN if empty. */
export function quantile(values: number[], q: number): number {
  if (values.length === 0) return NaN;
  const sorted = [...values].sort((a, b) => a - b);
  const position = (sorted.length - 1) * q;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

/**
 * Weighted quantile [q] ∈ [0, 1]: each value sits at the middle of its
 * weight on the cumulative axis, with linear interpolation in between
 * (equal weights give the usual midpoint quantile). NaN if empty.
 */
export function weightedQuantile(
  values: number[],
  weights: number[],
  q: number,
): number {
  const pairs = values
    .map((value, index) => ({ value, weight: weights[index] }))
    .filter((pair) => pair.weight > 0)
    .sort((a, b) => a.value - b.value);
  if (pairs.length === 0) return NaN;
  const total = pairs.reduce((sum, pair) => sum + pair.weight, 0);
  let cumulative = 0;
  const positions = pairs.map((pair) => {
    const position = (cumulative + pair.weight / 2) / total;
    cumulative += pair.weight;
    return position;
  });
  if (q <= positions[0]) return pairs[0].value;
  const last = pairs.length - 1;
  if (q >= positions[last]) return pairs[last].value;
  let i = 0;
  while (positions[i + 1] < q) i++;
  const share = (q - positions[i]) / (positions[i + 1] - positions[i]);
  return pairs[i].value + (pairs[i + 1].value - pairs[i].value) * share;
}

/** Effective number of observations of [weights] (Kish). */
export function effectiveCount(weights: number[]): number {
  const sum = weights.reduce((total, weight) => total + weight, 0);
  const squares = weights.reduce((total, weight) => total + weight * weight, 0);
  return squares === 0 ? 0 : (sum * sum) / squares;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/** Rounds to the nearest multiple of [step]. */
export function roundTo(value: number, step: number): number {
  return Math.round(value / step) * step;
}

/** Great-circle distance in metres. */
export function distanceM(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const rad = Math.PI / 180;
  const dLat = (lat2 - lat1) * rad;
  const dLng = (lng2 - lng1) * rad;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(a));
}

/** Months between two ISO dates (fractional, ≥ 0 when [to] is later). */
export function monthsBetween(from: string, to: string): number {
  const a = new Date(`${from.slice(0, 10)}T00:00:00Z`);
  const b = new Date(`${to.slice(0, 10)}T00:00:00Z`);
  return (b.getTime() - a.getTime()) / (1000 * 60 * 60 * 24 * 30.4375);
}

/** ISO date [months] before [date]. */
export function monthsBefore(date: string, months: number): string {
  const d = new Date(`${date.slice(0, 10)}T00:00:00Z`);
  d.setUTCMonth(d.getUTCMonth() - months);
  return d.toISOString().slice(0, 10);
}
