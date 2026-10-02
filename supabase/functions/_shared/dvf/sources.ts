// Public data sources of the estimate (all under Licence Ouverte 2.0):
// - geo-dvf commune files (files.data.gouv.fr, Etalab);
// - « Statistiques DVF » monthly medians (tabular-api.data.gouv.fr);
// - communes around a point (geo.api.gouv.fr).
import type { MonthlyStat } from "../estimation/trend.ts";
import type { PropertyType } from "../estimation/types.ts";

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

const TIMEOUT_MS = 20000;

async function fetchWithTimeout(
  fetcher: FetchLike,
  url: string,
  init: RequestInit = {},
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetcher(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/** Département folder of a commune code in geo-dvf (`971` for overseas). */
export function departmentOf(insee: string): string {
  return insee.startsWith("97") ? insee.slice(0, 3) : insee.slice(0, 2);
}

/** Départements without DVF data (Alsace-Moselle land register, Mayotte). */
export function hasDvfCoverage(insee: string): boolean {
  return !["57", "67", "68", "976"].includes(departmentOf(insee));
}

export function geoDvfUrl(insee: string, year: number): string {
  return `https://files.data.gouv.fr/geo-dvf/latest/csv/${year}/communes/` +
    `${departmentOf(insee)}/${insee}.csv`;
}

export type CsvDownload =
  | { status: "ok"; text: string; etag: string | null; lastModified: string | null }
  | { status: "not_modified" }
  | { status: "missing" };

/** Downloads a geo-dvf commune file, revalidated with its ETag. */
export async function downloadCommuneCsv(
  fetcher: FetchLike,
  insee: string,
  year: number,
  etag: string | null,
): Promise<CsvDownload> {
  const response = await fetchWithTimeout(fetcher, geoDvfUrl(insee, year), {
    headers: etag ? { "If-None-Match": etag } : {},
  });
  if (response.status === 304) {
    await response.body?.cancel();
    return { status: "not_modified" };
  }
  if (response.status === 404 || response.status === 403) {
    await response.body?.cancel();
    return { status: "missing" };
  }
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`geo-dvf ${insee}/${year}: HTTP ${response.status}`);
  }
  return {
    status: "ok",
    text: await response.text(),
    etag: response.headers.get("etag"),
    lastModified: response.headers.get("last-modified"),
  };
}

/** Paris, Lyon and Marseille: DVF and the BAN use the arrondissements. */
const PLM = new Set(["75056", "69123", "13055"]);

/** Points on a circle of [radiusM] around a point (plus the point itself). */
export function samplePoints(
  lat: number,
  lng: number,
  radiusM: number,
  count: number,
): [number, number][] {
  const points: [number, number][] = [[lat, lng]];
  const dLat = radiusM / 111320;
  const dLng = radiusM / (111320 * Math.cos((lat * Math.PI) / 180));
  for (let i = 0; i < count; i++) {
    const angle = (2 * Math.PI * i) / count;
    points.push([lat + dLat * Math.sin(angle), lng + dLng * Math.cos(angle)]);
  }
  return points;
}

/**
 * Codes of the communes (arrondissements in Paris / Lyon / Marseille)
 * containing the point or points up to 2 km around it.
 */
export async function communesAround(
  fetcher: FetchLike,
  lat: number,
  lng: number,
): Promise<string[]> {
  const points = [
    ...samplePoints(lat, lng, 1000, 4),
    ...samplePoints(lat, lng, 2000, 8).slice(1),
  ];
  const lookup = async ([pLat, pLng]: [number, number], arrondissement: boolean) => {
    const url = `https://geo.api.gouv.fr/communes?lat=${pLat.toFixed(5)}&lon=${pLng.toFixed(5)}` +
      `&fields=code${arrondissement ? "&type=arrondissement-municipal" : ""}`;
    const response = await fetchWithTimeout(fetcher, url);
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`geo.api: HTTP ${response.status}`);
    }
    const rows = (await response.json()) as { code: string }[];
    return rows.map((row) => row.code);
  };
  const codes = new Set<string>();
  await Promise.all(points.map(async (point) => {
    for (const code of await lookup(point, false)) {
      if (PLM.has(code)) {
        for (const arrondissement of await lookup(point, true)) codes.add(arrondissement);
      } else {
        codes.add(code);
      }
    }
  }));
  return [...codes].sort();
}

const STATS_URL =
  "https://tabular-api.data.gouv.fr/api/resources/03fba98d-885b-43c0-8986-d299cabc29da/data/";

export interface MonthlyStats {
  stats: MonthlyStat[];
  /** Parent area in the dataset (EPCI of a commune, département of an EPCI). */
  parent: string | null;
}

/** Monthly sales count and median €/m² of [codeGeo] for [type] (60 months). */
export async function monthlyStats(
  fetcher: FetchLike,
  codeGeo: string,
  type: PropertyType,
): Promise<MonthlyStats> {
  const url = `${STATS_URL}?code_geo__exact=${encodeURIComponent(codeGeo)}` +
    "&annee_mois__sort=desc&page_size=100";
  const response = await fetchWithTimeout(fetcher, url);
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`stats DVF ${codeGeo}: HTTP ${response.status}`);
  }
  const body = await response.json() as { data: Record<string, unknown>[] };
  const rows = body.data ?? [];
  return {
    parent: rows.length > 0 && typeof rows[0]["code_parent"] === "string"
      ? rows[0]["code_parent"] as string
      : null,
    stats: rows.map((row) => ({
      month: String(row["annee_mois"]),
      count: Number(row[`nb_ventes_${type}`] ?? 0) || 0,
      medianM2: Number(row[`med_prix_m2_${type}`] ?? 0) || 0,
    })),
  };
}

export interface CommuneCentre {
  code: string;
  lat: number;
  lng: number;
}

async function getJson<T>(fetcher: FetchLike, url: string, what: string): Promise<T> {
  const response = await fetchWithTimeout(fetcher, url);
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`${what}: HTTP ${response.status}`);
  }
  return await response.json() as T;
}

/** Communes (arrondissements in Paris / Lyon / Marseille) of a département, with their centre. */
export async function departmentCommunes(
  fetcher: FetchLike,
  department: string,
): Promise<CommuneCentre[]> {
  type Row = { code: string; centre?: { coordinates: [number, number] } };
  const base = `https://geo.api.gouv.fr/communes?codeDepartement=${department}&fields=code,centre`;
  const rows = await getJson<Row[]>(fetcher, base, "geo.api");
  if (rows.some((row) => PLM.has(row.code))) {
    rows.push(
      ...await getJson<Row[]>(fetcher, `${base}&type=arrondissement-municipal`, "geo.api"),
    );
  }
  return rows
    .filter((row) => !PLM.has(row.code) && row.centre)
    .map((row) => ({
      code: row.code,
      lng: row.centre!.coordinates[0],
      lat: row.centre!.coordinates[1],
    }));
}

/** Margin added to a radius to catch communes whose centre is farther out. */
const COMMUNE_MARGIN_M = 3000;

/**
 * Codes of the communes that may hold sales within [radiusM] of a point:
 * sampled points up to 2 km, then the communes of the départements met on
 * the circle whose centre is within the radius (+ 3 km). [departments]
 * caches the département lists between calls.
 */
export async function communesWithin(
  fetcher: FetchLike,
  lat: number,
  lng: number,
  radiusM: number,
  departments: Map<string, CommuneCentre[]>,
): Promise<string[]> {
  if (radiusM <= 2000) return await communesAround(fetcher, lat, lng);
  type Row = { codeDepartement: string };
  const codes = new Set<string>();
  const found = await Promise.all(
    samplePoints(lat, lng, radiusM, 8).map(([pLat, pLng]) =>
      getJson<Row[]>(
        fetcher,
        `https://geo.api.gouv.fr/communes?lat=${pLat.toFixed(5)}&lon=${pLng.toFixed(5)}` +
          "&fields=codeDepartement",
        "geo.api",
      )
    ),
  );
  const wanted = new Set(found.flat().map((row) => row.codeDepartement));
  for (const department of [...wanted].sort()) {
    if (!departments.has(department)) {
      departments.set(department, await departmentCommunes(fetcher, department));
    }
    for (const commune of departments.get(department)!) {
      const dLat = (commune.lat - lat) * 111320;
      const dLng = (commune.lng - lng) * 111320 * Math.cos((lat * Math.PI) / 180);
      if (Math.hypot(dLat, dLng) <= radiusM + COMMUNE_MARGIN_M) codes.add(commune.code);
    }
  }
  return [...codes].sort();
}
