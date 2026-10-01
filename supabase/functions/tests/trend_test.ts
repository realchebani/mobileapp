import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  curveFromMonthly,
  curveFromSales,
  projectionFactor,
  semesterOf,
  semestersEndingAt,
  yearOnYearPct,
} from "../_shared/estimation/trend.ts";
import { chaponostSales, sale } from "./helpers.ts";

const houses = chaponostSales().filter((s) => s.type === "maison");

Deno.test("semesters", () => {
  assertEquals(semesterOf("2025-06-30"), "2025-S1");
  assertEquals(semesterOf("2025-07-01"), "2025-S2");
  assertEquals(semestersEndingAt("2025-S1", 3), ["2024-S1", "2024-S2", "2025-S1"]);
});

Deno.test("curveFromSales on Chaponost houses", () => {
  const curve = curveFromSales(houses, "2025-12-19")!;
  assertEquals(curve.length, 10);
  assertEquals(curve[0], {
    semester: "2021-S1",
    medianM2: 4789,
    count: 24,
    scale: "commune",
    indexM2: 4927,
  });
  assertEquals(curve[9].semester, "2025-S2");
  assertEquals(curve[9].indexM2, 4284);
});

Deno.test("curveFromSales is null when a half-year is thin", () => {
  assertEquals(curveFromSales(houses.slice(0, 50), "2025-12-19"), null);
});

Deno.test("curveFromMonthly weights the monthly medians", () => {
  const stats = [];
  for (let year = 2021; year <= 2025; year++) {
    for (let month = 1; month <= 12; month++) {
      stats.push({
        month: `${year}-${String(month).padStart(2, "0")}`,
        count: month <= 6 ? 1 : 3,
        medianM2: month <= 6 ? 4000 : 4400,
      });
    }
  }
  stats.push({ month: "2019-01", count: 5, medianM2: 1 }, {
    month: "2025-01",
    count: 0,
    medianM2: 0,
  });
  const curve = curveFromMonthly(stats, "2025-12-31", "epci")!;
  assertEquals(curve.length, 10);
  assertEquals(curve[0], {
    semester: "2021-S1",
    medianM2: 4000,
    count: 6,
    scale: "epci",
    indexM2: 4200,
  });
  assertEquals(curve[1].medianM2, 4400);
  assertEquals(curveFromMonthly(stats.slice(0, 6), "2025-12-31", "departement"), null);
});

Deno.test("yearOnYearPct from sales, from the curve, or unknown", () => {
  assertEquals(yearOnYearPct(houses, "2025-12-19", null), 0.2);
  const curve = curveFromSales(houses, "2025-12-19")!;
  assertEquals(yearOnYearPct(houses.slice(0, 5), "2025-12-19", curve), 0.1);
  assertEquals(yearOnYearPct([], "2025-12-19", null), null);
});

Deno.test("projectionFactor uses the curve then a capped drift", () => {
  const curve = curveFromSales(houses, "2025-12-19")!;
  // 2021-S1 index 4927 → 2025-S2 index 4284, no drift.
  assertAlmostEquals(
    projectionFactor(curve, "2021-03-01", "2025-12-19", "2025-12-19", 0),
    4284 / 4927,
  );
  // Older than the curve: first point.
  assertAlmostEquals(
    projectionFactor(curve, "2019-03-01", "2025-12-19", "2025-12-19", 0),
    4284 / 4927,
  );
  // Unknown half-year after the curve: last point.
  assertAlmostEquals(projectionFactor(curve, "2026-03-01", "2025-12-19", "2025-12-19", 0), 1);
  // No curve, +20 %/year capped to +5 % over one year.
  assertAlmostEquals(
    projectionFactor(null, "2025-01-01", "2025-10-01", "2026-10-01", 20),
    1.05,
    0.001,
  );
  assertAlmostEquals(projectionFactor(null, "2025-01-01", "2025-10-01", "2026-10-01", null), 1);
  assertEquals(sale().type, "maison");
});
