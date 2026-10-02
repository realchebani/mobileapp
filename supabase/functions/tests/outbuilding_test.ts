import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  computeOutbuildingEstimate,
  countOutbuildingCandidates,
  latestOutbuildingSale,
  outbuildingExplanation,
} from "../_shared/estimation/outbuilding.ts";
import { frenchNumber } from "../_shared/estimation/explain.ts";
import type { OutbuildingSale, OutbuildingSubject } from "../_shared/estimation/types.ts";
import { loadOutbuildingMarket, type OutbuildingStore } from "../estimate-property/market.ts";

const subject: OutbuildingSubject = {
  type: "dependance",
  kind: "stationnement",
  lat: 45.7104,
  lng: 4.7469,
  insee: "69043",
  city: "Chaponost",
};

let counter = 0;
function garage(overrides: Partial<OutbuildingSale> = {}): OutbuildingSale {
  counter++;
  return {
    idMutation: `g${counter}`,
    insee: "69043",
    year: 2025,
    soldOn: "2025-06-15",
    priceEur: 20000,
    street: "Rue Test",
    lat: 45.7104,
    lng: 4.7469,
    ...overrides,
  };
}

/** [km] north of the subject. */
const north = (km: number) => 45.7104 + km / 111.32;

Deno.test("no estimate under 5 comparables", () => {
  const result = computeOutbuildingEstimate({
    subject,
    communeSales: [garage(), garage(), garage(), garage()],
    nearbySales: [],
    dataUntil: "2025-12-19",
    today: "2026-10-02",
  });
  assertEquals(result.status, "insufficient");
  assertEquals(result.reason, "too_few_sales");
  assertEquals(result.comparablesCount, 4);
});

Deno.test("median of single outbuilding sales, widened until 10", () => {
  const near = [15000, 18000, 20000, 22000, 25000, 30000].map((priceEur) =>
    garage({ priceEur, lat: north(0.3) })
  );
  const ring = [16000, 19000, 21000, 24000].map((priceEur) =>
    garage({ priceEur, insee: "69028", lat: north(1.5), street: "Rue Loin" })
  );
  const located = garage({ lat: null, lng: null });
  const result = computeOutbuildingEstimate({
    subject,
    communeSales: [...near, near[0], located],
    nearbySales: ring,
    dataUntil: "2025-12-19",
    today: "2026-10-02",
  });
  assertEquals(result.status, "ok");
  assertEquals(result.comparablesCount, 10);
  assertEquals(result.radiusM, 2000);
  assertEquals(result.months, 24);
  assert(result.lowEur! <= result.medianEur! && result.medianEur! <= result.highEur!);
  assertEquals(result.medianEur! % 500, 0);
  assert(result.medianEur! >= 18000 && result.medianEur! <= 22000);
  assertEquals(result.priceM2Median, null);
  assertEquals(result.semesterMedians, []);
  assertEquals(result.factors, []);
  assert(result.confidence! > 0 && result.confidence! <= 100);
  // Street shown only with at least 3 sales in it.
  const streets = new Set(result.comparables.map((c) => c.street));
  assertEquals(streets, new Set(["Rue Test", "Rue Loin"]));
  const first = result.comparables[0];
  assertEquals(first.type, "dependance");
  assertEquals(first.area_m2, null);
  assertEquals(first.price_m2_eur, null);
  assertEquals(result.sales12m, 8);
});

Deno.test("streets with fewer than 3 sales are hidden", () => {
  const sales = [1, 2, 3, 4, 5].map((i) => garage({ street: `Rue ${i}` }));
  const result = computeOutbuildingEstimate({
    subject,
    communeSales: sales,
    nearbySales: [],
    dataUntil: "2025-12-19",
    today: "2026-10-02",
  });
  assertEquals(result.comparables.every((c) => c.street === null), true);
});

Deno.test("candidates and latest sale", () => {
  const sales = [garage(), garage({ soldOn: "2020-01-01" }), garage({ lat: null })];
  assertEquals(countOutbuildingCandidates(subject, sales, "2025-12-19", 500, 24), 1);
  assertEquals(latestOutbuildingSale(sales), "2025-06-15");
  assertEquals(latestOutbuildingSale([]), null);
});

Deno.test("the explanation only uses the computed figures", () => {
  const result = computeOutbuildingEstimate({
    subject,
    communeSales: [1, 2, 3, 4, 5].map(() => garage()),
    nearbySales: [],
    dataUntil: "2025-12-19",
    today: "2026-10-02",
  });
  const text = outbuildingExplanation(subject, result, frenchNumber);
  assert(
    text.startsWith("D’après 5 ventes de garages, parkings et box vendus seuls à moins de 500 m"),
  );
  assert(text.includes(`${frenchNumber(20000)} €`));
  const cellar = outbuildingExplanation(
    { ...subject, kind: "dependance" },
    { ...result, radiusM: 2000, months: null },
    frenchNumber,
  );
  assert(cellar.includes("dépendances vendues seules"));
  assert(cellar.includes("à moins de 2 km"));
  const nowhere = outbuildingExplanation(
    subject,
    { ...result, radiusM: null, medianEur: null, lowEur: null, highEur: null },
    frenchNumber,
  );
  assert(nowhere.includes("dans votre secteur"));
});

function fakeStore(commune: OutbuildingSale[], nearby: OutbuildingSale[]) {
  const loads: [string[], number[]][] = [];
  const queries: unknown[] = [];
  const store: OutbuildingStore = {
    ensureLoaded: (insees, years) => {
      loads.push([insees, years]);
      return Promise.resolve(loads.length === 1 ? "Mon, 18 May 2026 13:10:01 GMT" : null);
    },
    communeOutbuildingSales: () => Promise.resolve(commune),
    nearbyOutbuildingSales: (options) => {
      queries.push(options);
      return Promise.resolve(nearby);
    },
  };
  return { store, loads, queries };
}

const centre = (code: string, km: number) => ({
  code,
  centre: { coordinates: [4.7469, north(km)] },
});

function fakeFetch(url: string) {
  const body = url.includes("codeDepartement=69")
    ? [centre("69043", 0), centre("69028", 1.5), centre("69100", 6)]
    : url.includes("fields=codeDepartement")
    ? [{ codeDepartement: "69" }]
    : url.includes("lat=45.72")
    ? [{ code: "69028" }]
    : [{ code: "69043" }];
  return Promise.resolve(new Response(JSON.stringify(body)));
}

const today = new Date("2026-10-01T10:00:00Z");

Deno.test("loadOutbuildingMarket stops at the first ring with enough sales", async () => {
  const sales = Array.from({ length: 10 }, () => garage({ soldOn: "2025-03-01" }));
  const { store, loads, queries } = fakeStore(sales, []);
  const market = await loadOutbuildingMarket(subject, store, fakeFetch, today);
  assertEquals(loads, [
    [["69043"], [2026, 2025, 2024, 2023, 2022, 2021]],
    [["69028"], [2025, 2024, 2023]],
  ]);
  assertEquals(queries.length, 1);
  assertEquals(market.dataUntil, "2025-03-01");
  assertEquals(market.sourceVersion, "geo-dvf 2026-05-18");
});

Deno.test("loadOutbuildingMarket widens, then loads older years", async () => {
  const { store, loads } = fakeStore([], []);
  const market = await loadOutbuildingMarket(subject, store, fakeFetch, today);
  assertEquals(market.dataUntil, null);
  assertEquals(market.sourceVersion, "geo-dvf 2026-05-18");
  // Rings 2, 5, 10 and 20 km, then the older years of the neighbours.
  assertEquals(loads.at(-1)![1], [2022, 2021, 2020]);
});

Deno.test("loadOutbuildingMarket respects its time budget", async () => {
  const { store } = fakeStore([], []);
  let time = 0;
  await assertRejects(
    () => loadOutbuildingMarket(subject, store, fakeFetch, today, () => (time += 60_000)),
    Error,
    "load budget exceeded",
  );
});

Deno.test("loadOutbuildingMarket without a source date", async () => {
  const { store } = fakeStore([], []);
  const quiet: OutbuildingStore = { ...store, ensureLoaded: () => Promise.resolve(null) };
  const market = await loadOutbuildingMarket(subject, quiet, fakeFetch, today);
  assertEquals(market.sourceVersion, "geo-dvf");
});
