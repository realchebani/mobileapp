// Server-side DVF cache (tables dvf_sources / dvf_sales, service role only).
// A commune × year file is downloaded once, cleaned and stored; it is
// revalidated with its ETag at most once every 7 days. Each file is stored
// as soon as it is processed, so an interrupted first load resumes on retry.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { cleanDvfCsv } from "../_shared/dvf/clean.ts";
import { downloadCommuneCsv, type FetchLike } from "../_shared/dvf/sources.ts";
import type { DvfSale, PropertyType } from "../_shared/estimation/types.ts";

const REVALIDATE_MS = 7 * 24 * 60 * 60 * 1000;
const PAGE = 1000;
const INSERT_CHUNK = 500;
const PARALLEL_DOWNLOADS = 4;

const SALE_COLUMNS =
  "id_mutation, insee, year, sold_on, property_type, price_eur, built_area_m2, rooms, land_m2, street, lat, lng";

interface SaleRow {
  id_mutation: string;
  insee: string;
  year: number;
  sold_on: string;
  property_type: PropertyType;
  price_eur: number;
  built_area_m2: number | string;
  rooms: number | null;
  land_m2: number | null;
  street: string | null;
  lat: number | null;
  lng: number | null;
}

function toSale(row: SaleRow): DvfSale {
  return {
    idMutation: row.id_mutation,
    insee: row.insee,
    year: row.year,
    soldOn: row.sold_on,
    type: row.property_type,
    priceEur: row.price_eur,
    areaM2: Number(row.built_area_m2),
    rooms: row.rooms,
    landM2: row.land_m2,
    street: row.street,
    lat: row.lat,
    lng: row.lng,
  };
}

function toRow(sale: DvfSale): SaleRow {
  return {
    id_mutation: sale.idMutation,
    insee: sale.insee,
    year: sale.year,
    sold_on: sale.soldOn,
    property_type: sale.type,
    price_eur: sale.priceEur,
    built_area_m2: sale.areaM2,
    rooms: sale.rooms,
    land_m2: sale.landM2,
    street: sale.street,
    lat: sale.lat,
    lng: sale.lng,
  };
}

/** Runs [task] on every item, [limit] at a time. */
async function inParallel<T>(items: T[], limit: number, task: (item: T) => Promise<void>) {
  const queue = [...items];
  await Promise.all(
    Array.from({ length: Math.min(limit, queue.length) }, async () => {
      while (queue.length > 0) await task(queue.shift()!);
    }),
  );
}

export class DvfStore {
  constructor(
    private readonly db: SupabaseClient,
    private readonly fetcher: FetchLike,
    private readonly now: () => Date,
  ) {}

  /**
   * Makes sure the files of [insees] × [years] are in the cache; returns the
   * most recent `Last-Modified` seen (source version).
   */
  async ensureLoaded(insees: string[], years: number[]): Promise<string | null> {
    const { data, error } = await this.db
      .from("dvf_sources")
      .select("insee, year, etag, last_modified, fetched_at")
      .in("insee", insees)
      .in("year", years);
    if (error) throw new Error(`dvf_sources: ${error.message}`);
    const known = new Map(
      (data ?? []).map((row) => [`${row.insee}|${row.year}`, row]),
    );
    let lastModified: string | null = null;
    const remember = (value: string | null | undefined) => {
      if (!value) return;
      if (lastModified === null || Date.parse(value) > Date.parse(lastModified)) {
        lastModified = value;
      }
    };
    const jobs: [string, number][] = [];
    for (const insee of insees) for (const year of years) jobs.push([insee, year]);
    await inParallel(jobs, PARALLEL_DOWNLOADS, async ([insee, year]) => {
      const source = known.get(`${insee}|${year}`);
      remember(source?.last_modified);
      const fresh = source &&
        this.now().getTime() - Date.parse(source.fetched_at) < REVALIDATE_MS;
      if (fresh) return;
      const download = await downloadCommuneCsv(this.fetcher, insee, year, source?.etag ?? null);
      const fetchedAt = this.now().toISOString();
      if (download.status === "not_modified") {
        await this.check(
          this.db.from("dvf_sources").update({ fetched_at: fetchedAt })
            .eq("insee", insee).eq("year", year),
        );
        return;
      }
      await this.check(this.db.from("dvf_sales").delete().eq("insee", insee).eq("year", year));
      if (download.status === "missing") {
        await this.check(
          this.db.from("dvf_sources").upsert({
            insee,
            year,
            etag: null,
            last_modified: null,
            fetched_at: fetchedAt,
            available: false,
            rows_kept: 0,
            rows_dropped: {},
          }),
        );
        return;
      }
      const { sales, dropped } = cleanDvfCsv(download.text, insee, year);
      for (let i = 0; i < sales.length; i += INSERT_CHUNK) {
        await this.check(
          this.db.from("dvf_sales").upsert(sales.slice(i, i + INSERT_CHUNK).map(toRow)),
        );
      }
      remember(download.lastModified);
      await this.check(
        this.db.from("dvf_sources").upsert({
          insee,
          year,
          etag: download.etag?.slice(0, 200) ?? null,
          last_modified: download.lastModified?.slice(0, 100) ?? null,
          fetched_at: fetchedAt,
          available: true,
          rows_kept: sales.length,
          rows_dropped: dropped,
        }),
      );
    });
    return lastModified;
  }

  /** Every cached sale of [type] in commune [insee]. */
  communeSales(insee: string, type: PropertyType): Promise<DvfSale[]> {
    return this.paged((from) =>
      this.db.from("dvf_sales").select(SALE_COLUMNS)
        .eq("insee", insee).eq("property_type", type)
        .order("id_mutation").range(from, from + PAGE - 1)
    );
  }

  /** Cached sales of [type] in [insees] inside a box, area range and period. */
  nearbySales(options: {
    insees: string[];
    type: PropertyType;
    box: { minLat: number; maxLat: number; minLng: number; maxLng: number };
    minArea: number;
    maxArea: number;
    since: string;
  }): Promise<DvfSale[]> {
    const { box } = options;
    return this.paged((from) =>
      this.db.from("dvf_sales").select(SALE_COLUMNS)
        .in("insee", options.insees).eq("property_type", options.type)
        .gte("lat", box.minLat).lte("lat", box.maxLat)
        .gte("lng", box.minLng).lte("lng", box.maxLng)
        .gte("built_area_m2", options.minArea).lte("built_area_m2", options.maxArea)
        .gt("sold_on", options.since)
        .order("id_mutation").order("insee").range(from, from + PAGE - 1)
    );
  }

  private async paged(
    // deno-lint-ignore no-explicit-any
    page: (from: number) => PromiseLike<{ data: any[] | null; error: { message: string } | null }>,
  ): Promise<DvfSale[]> {
    const sales: DvfSale[] = [];
    for (let from = 0;; from += PAGE) {
      const { data, error } = await page(from);
      if (error) throw new Error(`dvf_sales: ${error.message}`);
      sales.push(...(data ?? []).map(toSale));
      if (!data || data.length < PAGE) return sales;
    }
  }

  private async check(
    query: PromiseLike<{ error: { message: string } | null }>,
  ): Promise<void> {
    const { error } = await query;
    if (error) throw new Error(`dvf cache: ${error.message}`);
  }
}
