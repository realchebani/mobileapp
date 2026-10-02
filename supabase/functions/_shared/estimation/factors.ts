// Non-quantified factors listed under « Ce qui influence votre estimation »
// (v1 has no adjustment: these factors carry no figure effect).
import type { Factor, Subject } from "./types.ts";
import { median } from "./stats.ts";

const MAX_FACTORS = 8;
const MAX_FREE_TEXT = 3;

/**
 * Deterministic factors from the seller's answers. [comparableLand] are the
 * land areas of the comparables (to tell a large or small plot), [year] the
 * current year.
 */
export function buildFactors(
  subject: Subject,
  comparableLand: number[],
  year: number,
): Factor[] {
  const plus: Factor[] = [];
  const minus: Factor[] = [];
  const equipment = new Set(subject.outdoorEquipment);
  if (subject.constructionYear !== null && subject.constructionYear >= year - 10) {
    plus.push({ sign: "+", label: `Construction récente (${subject.constructionYear})` });
  }
  if (subject.heatPumpYear !== null && subject.heatPumpYear >= year - 5) {
    plus.push({ sign: "+", label: `Pompe à chaleur installée en ${subject.heatPumpYear}` });
  }
  if (subject.roofYear !== null && subject.roofYear >= year - 10) {
    plus.push({ sign: "+", label: `Toiture refaite en ${subject.roofYear}` });
  }
  if (equipment.has("piscine")) plus.push({ sign: "+", label: "Piscine" });
  if (equipment.has("garage")) plus.push({ sign: "+", label: "Garage" });
  if (equipment.has("terrasse")) plus.push({ sign: "+", label: "Terrasse" });
  const land = subject.landM2;
  if (subject.type === "maison" && land !== null && comparableLand.length >= 5) {
    const typical = median(comparableLand);
    if (land > 1.5 * typical) {
      plus.push({ sign: "+", label: "Terrain plus grand que celui des ventes comparables" });
    } else if (land < 0.5 * typical) {
      minus.push({ sign: "-", label: "Terrain plus petit que celui des ventes comparables" });
    }
  }
  for (const asset of subject.assets.slice(0, MAX_FREE_TEXT)) {
    plus.push({ sign: "+", label: asset.trim() });
  }
  if (subject.noiseLevel !== null && subject.noiseLevel >= 7) {
    minus.push({ sign: "-", label: "Environnement bruyant" });
  }
  if (subject.overlooking === "important") {
    minus.push({ sign: "-", label: "Vis-à-vis important" });
  }
  for (const watchPoint of subject.watchPoints.slice(0, MAX_FREE_TEXT)) {
    minus.push({ sign: "-", label: watchPoint.trim() });
  }
  const minusSlots = Math.min(minus.length, Math.max(MAX_FACTORS - plus.length, 3));
  return [...plus.slice(0, MAX_FACTORS - minusSlots), ...minus.slice(0, minusSlots)]
    .filter((factor) => factor.label !== "");
}
