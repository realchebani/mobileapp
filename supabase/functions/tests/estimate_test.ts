import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  computeEstimate,
  countCandidates,
  displayDistance,
  insufficient,
  latestSaleDate,
} from "../_shared/estimation/estimate.ts";
import { curveFromSales } from "../_shared/estimation/trend.ts";
import { buildFactors } from "../_shared/estimation/factors.ts";
import { chaponostSales, sale, sparseRuralSales, subject } from "./helpers.ts";

const houses = chaponostSales().filter((s) => s.type === "maison");
const dataUntil = latestSaleDate(houses)!;
const curve = curveFromSales(houses, dataUntil);

Deno.test("latestSaleDate", () => {
  assertEquals(dataUntil, "2025-12-19");
  assertEquals(latestSaleDate([]), null);
});

Deno.test("displayDistance rounds to 100 m", () => {
  assertEquals(displayDistance(null), null);
  assertEquals(displayDistance(12), 100);
  assertEquals(displayDistance(374), 400);
  assertEquals(displayDistance(1234), 1200);
});

Deno.test("Chaponost house of 115 m²: 500 m and 2 years are enough", () => {
  const result = computeEstimate({
    subject: subject({ outdoorEquipment: ["piscine"] }),
    communeSales: houses,
    nearbySales: [],
    curve,
    dataUntil,
    today: "2026-10-01",
  });
  assertEquals(result.status, "ok");
  assertEquals(result.reason, null);
  assertEquals(
    [result.lowEur, result.medianEur, result.highEur],
    [419000, 476000, 540000],
  );
  assertEquals(
    [result.priceM2Low, result.priceM2Median, result.priceM2High],
    [3595, 4136, 4634],
  );
  assertEquals(result.confidence, 78);
  assertEquals(result.comparablesCount, 18);
  assertEquals([result.scope, result.radiusM, result.months], ["radius", 500, 24]);
  assertEquals(result.sales12m, 62);
  assertEquals(result.yoyChangePct, 0.2);
  assertEquals(result.semesterMedians.length, 10);
  assertEquals(result.factors, [{ sign: "+", label: "Piscine" }]);
  // Weighted order, rounded distance, street only with ≥ 3 sales in it.
  const first = result.comparables[0];
  assertEquals(first.sold_year, 2025);
  assert(result.comparables.every((c) => !("sold_on" in c)));
  assertEquals(first.distance_m, 400);
  assert(result.comparables.some((c) => c.street === null));
  assert(result.comparables.some((c) => c.street === "Rue Hippolyte Bonnet"));
  for (const c of result.comparables) assert(c.area_m2! >= 80 && c.area_m2! <= 150);
  // Median within the range, range within ±5 %…±20 %.
  assert(result.lowEur! <= result.medianEur! && result.medianEur! <= result.highEur!);
  assert(result.highEur! / result.medianEur! <= 1.21);
});

Deno.test("fewer than 5 comparables: no estimate", () => {
  const result = computeEstimate({
    subject: subject(),
    communeSales: [sale(), sale(), sale(), sale()],
    nearbySales: [],
    curve: null,
    dataUntil: "2025-12-19",
    today: "2026-10-01",
  });
  assertEquals(result.status, "insufficient");
  assertEquals(result.reason, "too_few_sales");
  assertEquals(result.comparablesCount, 4);
  assertEquals(result.lowEur, null);
  assertEquals(result.sales12m, 4);
});

Deno.test("sparse rural area: widens the geography first, on recent sales", () => {
  const result = computeEstimate({
    subject: subject({ roomsCount: null, constructionYear: null, landM2: null }),
    communeSales: [],
    nearbySales: sparseRuralSales(),
    curve: null,
    dataUntil: "2025-12-19",
    today: "2026-10-01",
  });
  assertEquals(result.status, "ok");
  // 4 recent sales within 5 km, 12 recent ones within 10 km: 10 km, 2 years
  // (not 5 km with older sales).
  assertEquals([result.radiusM, result.months], [10000, 24]);
  assertEquals(result.comparablesCount, 12);
  assert(result.confidence! < 60);
});

Deno.test("widens the period only when the widest radius is too sparse", () => {
  const old = Array.from(
    { length: 6 },
    (_, i) => sale({ soldOn: "2022-03-01", lat: 45.85, priceEur: 450000 + i * 5000 }),
  );
  const result = computeEstimate({
    subject: subject(),
    communeSales: [],
    // A sale without coordinates and an apartment are ignored.
    nearbySales: [...old, sale({ lat: null, lng: null }), sale({ type: "appartement" }), old[0]],
    curve: null,
    dataUntil: "2025-12-19",
    today: "2026-10-01",
  });
  assertEquals(result.status, "ok");
  assertEquals([result.radiusM, result.months], [20000, 60]);
  assertEquals(result.comparablesCount, 6);
});

Deno.test("countCandidates counts each sale once within radius and period", () => {
  const sales = sparseRuralSales();
  assertEquals(countCandidates(subject(), sales, "2025-12-19", 5000, 24), 4);
  assertEquals(countCandidates(subject(), sales, "2025-12-19", 10000, 24), 12);
  assertEquals(countCandidates(subject(), [...sales, sales[0]], "2025-12-19", 20000, 60), 20);
  assertEquals(countCandidates(subject(), [sale({ lat: null })], "2025-12-19", 20000, 60), 0);
});

Deno.test("outliers outside 1.5 × IQR of the commune are dropped", () => {
  const regular = Array.from({ length: 10 }, (_, i) => sale({ priceEur: 450000 + i * 2000 }));
  const outlier = sale({ priceEur: 1500000 });
  const result = computeEstimate({
    subject: subject(),
    communeSales: [...regular, outlier],
    nearbySales: [],
    curve: null,
    dataUntil: "2025-12-19",
    today: "2026-10-01",
  });
  assertEquals(result.comparablesCount, 10);
});

Deno.test("insufficient() builds an empty result", () => {
  const result = insufficient("unsupported_type");
  assertEquals(result.status, "insufficient");
  assertEquals(result.reason, "unsupported_type");
  assertEquals(result.comparables, []);
});

Deno.test("buildFactors lists positive then negative factors", () => {
  const factors = buildFactors(
    subject({
      constructionYear: 2020,
      heatPumpYear: 2023,
      roofYear: 2018,
      outdoorEquipment: ["piscine", "garage", "terrasse"],
      landM2: 2000,
      noiseLevel: 8,
      overlooking: "important",
      assets: ["École à 4 min", " ", "Parc", "Marché"],
      watchPoints: ["Circulation le matin"],
    }),
    [500, 500, 600, 400, 500],
    2026,
  );
  assertEquals(factors.map((f) => f.sign + f.label), [
    "+Construction récente (2020)",
    "+Pompe à chaleur installée en 2023",
    "+Toiture refaite en 2018",
    "+Piscine",
    "+Garage",
    "-Environnement bruyant",
    "-Vis-à-vis important",
    "-Circulation le matin",
  ]);
  assertEquals(
    buildFactors(subject({ landM2: 100 }), [500, 500, 600, 400, 500], 2026),
    [{ sign: "-", label: "Terrain plus petit que celui des ventes comparables" }],
  );
  assertEquals(
    buildFactors(subject({ landM2: 2000, type: "maison" }), [500, 500, 600, 400, 500], 2026),
    [{ sign: "+", label: "Terrain plus grand que celui des ventes comparables" }],
  );
  assertEquals(buildFactors(subject({ landM2: 520 }), [500, 500, 600, 400, 500], 2026), []);
});
