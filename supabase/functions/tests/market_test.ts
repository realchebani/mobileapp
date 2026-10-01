import { assertEquals } from "jsr:@std/assert@1";
import { loadMarket, type SalesStore } from "../estimate-property/market.ts";
import type { DvfSale } from "../_shared/estimation/types.ts";
import { chaponostSales, sale, subject } from "./helpers.ts";

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

/** geo.api answers Chaponost + Brindas; the stats API answers [stats]. */
function fakeFetch(stats: Record<string, unknown[]> = {}) {
  return (url: string) => {
    if (url.startsWith("https://geo.api.gouv.fr")) {
      return Promise.resolve(
        new Response(
          JSON.stringify(url.includes("lat=45.72") ? [{ code: "69028" }] : [{ code: "69043" }]),
        ),
      );
    }
    const code = new URL(url).searchParams.get("code_geo__exact")!;
    if (!(code in stats)) return Promise.resolve(new Response("x", { status: 500 }));
    return Promise.resolve(new Response(JSON.stringify({ data: stats[code] })));
  };
}

Deno.test("loads the commune (5 years + current), neighbours (4 years) and the curve", async () => {
  const { store, loads, queries } = fakeStore(houses, [
    sale({ insee: "69028", soldOn: "2025-02-01" }),
  ]);
  const market = await loadMarket(subject(), store, fakeFetch(), new Date("2026-10-01T10:00:00Z"));
  assertEquals(loads, [
    [["69043"], [2026, 2025, 2024, 2023, 2022, 2021]],
    [["69028"], [2025, 2024, 2023, 2022]],
  ]);
  const query = queries[0] as { insees: string[]; minArea: number; since: string };
  assertEquals(query.insees, ["69043", "69028"]);
  assertEquals(Math.round(query.minArea), 81);
  assertEquals(query.since, "2021-12-31");
  assertEquals(market.dataUntil, "2025-12-19");
  assertEquals(market.curve![0].scale, "commune");
  assertEquals(market.sourceVersion, "geo-dvf 2026-05-18");
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
