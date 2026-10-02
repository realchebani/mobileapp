import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { loadMarket, type SalesStore } from "../estimate-property/market.ts";
import type { DvfSale } from "../_shared/estimation/types.ts";
import { chaponostSales, sale, sparseRuralSales, subject } from "./helpers.ts";

const houses = chaponostSales().filter((s) => s.type === "maison");

function fakeStore(commune: DvfSale[], nearby: DvfSale[]) {
  const loads: [string[], number[]][] = [];
  const queries: unknown[] = [];
  const store: SalesStore = {
    ensureLoaded: (insees, years) => {
      loads.push([insees, years]);
      return Promise.resolve(loads.length === 1 ? "Mon, 18 May 2026 13:10:01 GMT" : null);
    },
    communeSales: () => Promise.resolve(commune),
    nearbySales: (options) => {
      queries.push(options);
      return Promise.resolve(nearby);
    },
  };
  return { store, loads, queries };
}

/** Centre of a commune [km] north of the subject. */
const north = (code: string, km: number) => ({
  code,
  centre: { coordinates: [4.7469, 45.7104 + km / 111.32] },
});

/**
 * geo.api: Chaponost + Brindas (69028) up to 2 km; département 69 with
 * communes whose centre is 1.5 km (69028), 6 km (69100), 12 km (69200) and
 * 40 km (69300) away. The stats API answers [stats].
 */
function fakeFetch(stats: Record<string, unknown[]> = {}) {
  return (url: string) => {
    if (url.startsWith("https://geo.api.gouv.fr")) {
      const body = url.includes("codeDepartement=69")
        ? [
          north("69043", 0),
          north("69028", 1.5),
          north("69100", 6),
          north("69200", 12),
          north("69300", 40),
          { code: "69999" },
        ]
        : url.includes("fields=codeDepartement")
        ? [{ codeDepartement: "69" }]
        : url.includes("lat=45.72")
        ? [{ code: "69028" }]
        : [{ code: "69043" }];
      return Promise.resolve(new Response(JSON.stringify(body)));
    }
    const code = new URL(url).searchParams.get("code_geo__exact")!;
    if (!(code in stats)) return Promise.resolve(new Response("x", { status: 500 }));
    return Promise.resolve(new Response(JSON.stringify({ data: stats[code] })));
  };
}

const today = new Date("2026-10-01T10:00:00Z");

Deno.test("a dense commune: the 2 km ring and the 3 recent years are enough", async () => {
  const { store, loads, queries } = fakeStore(houses, [
    sale({ insee: "69028", soldOn: "2025-02-01" }),
  ]);
  const market = await loadMarket(subject(), store, fakeFetch(), today);
  assertEquals(loads, [
    [["69043"], [2026, 2025, 2024, 2023, 2022, 2021]],
    [["69028"], [2025, 2024, 2023]],
  ]);
  const query = queries[0] as { insees: string[]; minArea: number; since: string };
  assertEquals(query.insees, ["69043", "69028"]);
  assertEquals(Math.round(query.minArea), 81);
  assertEquals(query.since, "2019-12-31");
  assertEquals(queries.length, 1);
  assertEquals(market.dataUntil, "2025-12-19");
  assertEquals(market.curve![0].scale, "commune");
  assertEquals(market.sourceVersion, "geo-dvf 2026-05-18");
});

Deno.test("sparse rural area: loads the rings progressively until 10 recent sales", async () => {
  const { store, loads, queries } = fakeStore([], sparseRuralSales());
  const market = await loadMarket(subject(), store, fakeFetch(), today);
  assertEquals(loads, [
    [["69043"], [2026, 2025, 2024, 2023, 2022, 2021]],
    [["69028"], [2025, 2024, 2023]],
    [["69100"], [2025, 2024, 2023]],
    [["69200"], [2025, 2024, 2023]],
  ]);
  assertEquals(queries.length, 3);
  assertEquals(market.dataUntil, "2025-05-10");
});

Deno.test("widest ring still sparse: loads 5 years", async () => {
  const far = Array.from({ length: 3 }, () => sale({ soldOn: "2025-03-01", lat: 45.85 }));
  const { store, loads } = fakeStore([], far);
  await loadMarket(subject(), store, fakeFetch(), today);
  assertEquals(loads.at(-1), [["69028", "69100", "69200"], [2022, 2021, 2020]]);
});

Deno.test("stops when the loading budget is exceeded", async () => {
  let t = 0;
  const { store } = fakeStore([], []);
  await assertRejects(
    () => loadMarket(subject(), store, fakeFetch(), today, () => (t += 60_000)),
    Error,
    "load budget exceeded",
  );
});

function months(count: number, median: number) {
  const rows = [];
  for (let year = 2021; year <= 2025; year++) {
    for (let month = 1; month <= 12; month++) {
      rows.push({
        annee_mois: `${year}-${String(month).padStart(2, "0")}`,
        code_parent: "P",
        nb_ventes_maison: count,
        med_prix_m2_maison: median,
      });
    }
  }
  return rows;
}

Deno.test("falls back to the EPCI then the département statistics", async () => {
  const few = [sale({ soldOn: "2025-12-01" })];
  const epci = await loadMarket(
    subject(),
    fakeStore(few, []).store,
    fakeFetch({
      "69043": [{ annee_mois: "2025-12", code_parent: "200046977" }],
      "200046977": months(5, 4000),
    }),
    new Date("2026-10-01T10:00:00Z"),
  );
  assertEquals(epci.curve![0].scale, "epci");
  assertEquals(epci.sourceVersion, "geo-dvf 2026-05-18 stats DVF epci");

  const department = await loadMarket(
    subject(),
    fakeStore(few, []).store,
    fakeFetch({
      "69043": [{ annee_mois: "2025-12", code_parent: "E" }],
      "E": [{
        annee_mois: "2025-12",
        code_parent: "69",
        nb_ventes_maison: 1,
        med_prix_m2_maison: 1,
      }],
      "69": months(50, 3500),
    }),
    new Date("2026-10-01T10:00:00Z"),
  );
  assertEquals(department.curve![0].scale, "departement");

  const none = await loadMarket(
    subject(),
    fakeStore(few, []).store,
    fakeFetch(),
    new Date("2026-10-01T10:00:00Z"),
  );
  assertEquals(none.curve, null);
  const national = await loadMarket(
    subject(),
    fakeStore(few, []).store,
    fakeFetch({
      "69043": [{ annee_mois: "2025-12", code_parent: "E" }],
      "E": [{ annee_mois: "2025-12", code_parent: "nation" }],
    }),
    new Date("2026-10-01T10:00:00Z"),
  );
  assertEquals(national.curve, null);
  const orphan = await loadMarket(
    subject(),
    fakeStore(few, []).store,
    fakeFetch({ "69043": [] }),
    new Date("2026-10-01T10:00:00Z"),
  );
  assertEquals(orphan.curve, null);
});

Deno.test("no sale at all: no data date, no curve", async () => {
  const market = await loadMarket(
    subject({ lat: 45.73 }),
    fakeStore([], []).store,
    () => Promise.resolve(new Response(JSON.stringify([{ code: "69043" }]))),
    new Date("2026-10-01T10:00:00Z"),
  );
  assertEquals(market.dataUntil, null);
  assertEquals(market.curve, null);
  assertEquals(market.sourceVersion, "geo-dvf 2026-05-18");
});
