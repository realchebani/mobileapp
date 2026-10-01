import { assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";
import {
  clamp,
  distanceM,
  effectiveCount,
  median,
  monthsBefore,
  monthsBetween,
  quantile,
  roundTo,
  weightedQuantile,
} from "../_shared/estimation/stats.ts";

Deno.test("median and quantiles", () => {
  assertEquals(median([3, 1, 2]), 2);
  assertEquals(median([4, 1, 2, 3]), 2.5);
  assertEquals(Number.isNaN(median([])), true);
  assertEquals(quantile([1, 2, 3, 4, 5], 0.25), 2);
});

Deno.test("weightedQuantile", () => {
  assertEquals(weightedQuantile([1, 2, 3], [1, 1, 1], 0.5), 2);
  assertEquals(weightedQuantile([1, 2, 3], [1, 1, 1], 0), 1);
  assertEquals(weightedQuantile([1, 2, 3], [1, 1, 1], 1), 3);
  assertEquals(weightedQuantile([10, 20], [1, 1], 0.5), 15);
  // A heavy weight pulls the median.
  assertAlmostEquals(weightedQuantile([10, 20, 30], [1, 1, 6], 0.5), 190 / 7);
  assertEquals(weightedQuantile([5, 6], [0, 1], 0.5), 6);
  assertEquals(Number.isNaN(weightedQuantile([], [], 0.5)), true);
});

Deno.test("effectiveCount, clamp, roundTo", () => {
  assertEquals(effectiveCount([1, 1, 1, 1]), 4);
  assertEquals(effectiveCount([]), 0);
  assertEquals(clamp(5, 0, 3), 3);
  assertEquals(clamp(-1, 0, 3), 0);
  assertEquals(roundTo(478600, 1000), 479000);
});

Deno.test("distance and months", () => {
  assertAlmostEquals(distanceM(45.7104, 4.7469, 45.7194, 4.7469), 1000.8, 1);
  assertAlmostEquals(monthsBetween("2025-01-01", "2026-01-01"), 12, 0.05);
  assertEquals(monthsBefore("2025-12-19", 36), "2022-12-19");
});
