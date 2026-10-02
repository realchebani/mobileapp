import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { DvfStore } from "../estimate-property/store.ts";

type Result = { data?: unknown; error: { message: string } | null };

/** Chainable fake of the supabase-js query builder recording every call. */
function fakeDb(answer: (table: string, calls: string[]) => Result) {
  const log: string[] = [];
  const builder = (table: string) => {
    const calls: string[] = [];
    const chain: Record<string, unknown> = {};
    for (
      const method of [
        "select",
        "update",
        "delete",
        "upsert",
        "eq",
        "in",
        "gte",
        "lte",
        "gt",
        "order",
        "range",
      ]
    ) {
      chain[method] = (...args: unknown[]) => {
        calls.push(`${method}(${JSON.stringify(args).slice(1, -1).slice(0, 2000)})`);
        return chain;
      };
    }
    chain.then = (resolve: (r: Result) => unknown) => {
      log.push(`${table}.${calls.join(".")}`);
      return Promise.resolve(answer(table, calls)).then(resolve);
    };
    return chain;
  };
  return { db: { from: builder } as unknown as SupabaseClient, log };
}

const CSV = [
  "id_mutation,date_mutation,nature_mutation,valeur_fonciere,adresse_nom_voie,id_parcelle,type_local,surface_reelle_bati,nombre_pieces_principales,surface_terrain,longitude,latitude",
  "m1,2025-03-02,Vente,400000,RUE A,P1,Maison,100,5,500,4.7,45.7",
  "m2,2025-03-02,Vente,1000,,P2,Dépendance,,,,,",
].join("\n");

const now = () => new Date("2026-10-01T10:00:00Z");

Deno.test("ensureLoaded downloads, stores, revalidates and skips fresh files", async () => {
  const sources = [
    // fresh: skipped
    {
      insee: "69043",
      year: 2025,
      etag: '"a"',
      last_modified: "Mon, 18 May 2026 13:10:01 GMT",
      fetched_at: "2026-09-30T10:00:00Z",
      format_version: 2,
    },
    // stale: revalidated (304)
    {
      insee: "69043",
      year: 2024,
      etag: '"b"',
      last_modified: "Sun, 17 May 2026 13:10:01 GMT",
      fetched_at: "2026-09-01T10:00:00Z",
      format_version: 2,
    },
  ];
  const { db, log } = fakeDb((table, calls) =>
    table === "dvf_sources" && calls[0].startsWith("select")
      ? { data: sources, error: null }
      : { error: null }
  );
  const urls: string[] = [];
  const store = new DvfStore(db, (url) => {
    urls.push(url);
    if (url.includes("/2024/")) return Promise.resolve(new Response(null, { status: 304 }));
    if (url.includes("/2023/")) return Promise.resolve(new Response("", { status: 404 }));
    return Promise.resolve(
      new Response(CSV, {
        headers: { etag: '"c"', "last-modified": "Tue, 19 May 2026 13:10:01 GMT" },
      }),
    );
  }, now);
  const lastModified = await store.ensureLoaded(["69043"], [2025, 2024, 2023, 2022]);
  assertEquals(lastModified, "Tue, 19 May 2026 13:10:01 GMT");
  assertEquals(urls.length, 3);
  const writes = log.filter((l) => !l.startsWith("dvf_sources.select"));
  assertEquals(
    writes.some((l) => l.startsWith("dvf_sources.update") && l.includes('"year",2024')),
    true,
  );
  assertEquals(
    writes.some((l) => l.startsWith("dvf_sales.delete") && l.includes('"year",2023')),
    true,
  );
  assertEquals(
    writes.some((l) => l.startsWith("dvf_sources.upsert") && l.includes('"available":false')),
    true,
  );
  assertEquals(writes.some((l) => l.startsWith("dvf_sales.upsert") && l.includes("m1")), true);
  assertEquals(
    // The house and the outbuilding sold alone (m2).
    writes.some((l) => l.startsWith("dvf_sources.upsert") && l.includes('"rows_kept":2')),
    true,
  );
});

Deno.test("ensureLoaded reloads in full the files cleaned by an older version", async () => {
  const sources = [{
    insee: "69043",
    year: 2025,
    etag: '"a"',
    last_modified: "Mon, 18 May 2026 13:10:01 GMT",
    fetched_at: "2026-09-30T10:00:00Z",
  }];
  const { db, log } = fakeDb((table, calls) =>
    table === "dvf_sources" && calls[0].startsWith("select")
      ? { data: sources, error: null }
      : { error: null }
  );
  const headers: (string | null)[] = [];
  const store = new DvfStore(db, (_url, init) => {
    headers.push(new Headers(init?.headers).get("If-None-Match"));
    return Promise.resolve(new Response(CSV));
  }, now);
  await store.ensureLoaded(["69043"], [2025]);
  assertEquals(headers, [null]);
  const upsert = log.find((l) => l.startsWith("dvf_sales.upsert"))!;
  assertEquals(upsert.includes('"property_type":"dependance"'), true);
  assertEquals(upsert.includes('"built_area_m2":null'), true);
  assertEquals(
    log.some((l) => l.startsWith("dvf_sources.upsert") && l.includes('"format_version":2')),
    true,
  );
});

Deno.test("ensureLoaded surfaces database errors", async () => {
  const failing = new DvfStore(fakeDb(() => ({ error: { message: "down" } })).db, fetch, now);
  await assertRejects(() => failing.ensureLoaded(["69043"], [2025]), Error, "dvf_sources: down");
  const writeFails = new DvfStore(
    fakeDb((table, calls) =>
      table === "dvf_sources" && calls[0].startsWith("select")
        ? { data: null, error: null }
        : { error: { message: "ro" } }
    ).db,
    () => Promise.resolve(new Response(CSV)),
    now,
  );
  await assertRejects(() => writeFails.ensureLoaded(["69043"], [2025]), Error, "dvf cache: ro");
});

const row = (i: number) => ({
  id_mutation: `m${i}`,
  insee: "69043",
  year: 2025,
  sold_on: "2025-03-02",
  property_type: "maison",
  price_eur: 400000,
  built_area_m2: "100.00",
  rooms: 5,
  land_m2: 500,
  street: "Rue A",
  lat: 45.7,
  lng: 4.7,
});

Deno.test("communeSales and nearbySales page through the cache", async () => {
  const { db, log } = fakeDb((_table, calls) => {
    const range = calls.find((c) => c.startsWith("range"))!;
    const from = Number(range.slice(6).split(",")[0]);
    const count = from === 0 ? 1000 : 3;
    return { data: Array.from({ length: count }, (_, i) => row(from + i)), error: null };
  });
  const store = new DvfStore(db, fetch, now);
  const sales = await store.communeSales("69043", "maison");
  assertEquals(sales.length, 1003);
  assertEquals(sales[0].areaM2, 100);
  assertEquals(sales[0].soldOn, "2025-03-02");
  const nearby = await store.nearbySales({
    insees: ["69043"],
    type: "maison",
    box: { minLat: 45, maxLat: 46, minLng: 4, maxLng: 5 },
    minArea: 80,
    maxArea: 150,
    since: "2021-12-31",
  });
  assertEquals(nearby.length, 1003);
  assertEquals(log.length, 4);
  const failing = new DvfStore(
    fakeDb(() => ({ data: null, error: { message: "x" } })).db,
    fetch,
    now,
  );
  await assertRejects(() => failing.communeSales("69043", "maison"), Error, "dvf_sales: x");
});

Deno.test("outbuilding sales page through the cache", async () => {
  const { db, log } = fakeDb(() => ({
    data: [{ ...row(1), property_type: "dependance", built_area_m2: null, price_eur: 15000 }],
    error: null,
  }));
  const store = new DvfStore(db, fetch, now);
  const commune = await store.communeOutbuildingSales("69043");
  assertEquals(commune, [{
    idMutation: "m1",
    insee: "69043",
    year: 2025,
    soldOn: "2025-03-02",
    priceEur: 15000,
    street: "Rue A",
    lat: 45.7,
    lng: 4.7,
  }]);
  const nearby = await store.nearbyOutbuildingSales({
    insees: ["69043"],
    box: { minLat: 45, maxLat: 46, minLng: 4, maxLng: 5 },
    since: "2021-12-31",
  });
  assertEquals(nearby.length, 1);
  assertEquals(log.every((l) => l.includes('"property_type","dependance"')), true);
  assertEquals(log.some((l) => l.includes('gte("built_area_m2"')), false);
});
