// Turns the dossier read with the user's JWT into the estimate's subject,
// or the reason why there can be no estimate.
import { hasDvfCoverage } from "../_shared/dvf/sources.ts";
import type { InsufficientReason, Subject } from "../_shared/estimation/types.ts";

/** Columns of `properties` read by the function. */
export const PROPERTY_COLUMNS = [
  "id",
  "owner_id",
  "status",
  "property_type",
  "lat",
  "lng",
  "address_citycode",
  "address_city",
  "living_area_m2",
  "rooms_count",
  "construction_year",
  "heat_pump_year",
  "roof_year",
  "outdoor_equipment",
  "pool_type",
  "noise_level",
  "overlooking",
].join(", ");

export interface PropertyRow {
  id: string;
  owner_id: string;
  status: string;
  property_type: string | null;
  lat: number | null;
  lng: number | null;
  address_citycode: string | null;
  address_city: string | null;
  living_area_m2: number | string | null;
  rooms_count: number | null;
  construction_year: number | null;
  heat_pump_year: number | null;
  roof_year: number | null;
  outdoor_equipment: string[] | null;
  pool_type: string | null;
  noise_level: number | null;
  overlooking: string | null;
}

export interface Dossier {
  property: PropertyRow;
  parcelAreas: (number | null)[];
  lifestyle: { kind: string; label: string }[];
  documents: { kind: string; status: string }[];
}

/** Documents needed to send a dossier (same rule as V7). */
export const REQUIRED_DOCUMENTS = ["titre_propriete", "piece_identite"];

/** Whether [dossier] has a non-rejected title deed and identity document. */
export function hasRequiredDocuments(dossier: Dossier): boolean {
  return REQUIRED_DOCUMENTS.every((kind) =>
    dossier.documents.some((d) => d.kind === kind && d.status !== "rejected")
  );
}

export function toSubject(dossier: Dossier): Subject | InsufficientReason {
  const p = dossier.property;
  if (p.property_type !== "maison" && p.property_type !== "appartement") {
    return "unsupported_type";
  }
  const insee = p.address_citycode ?? "";
  if (p.lat === null || p.lng === null || !/^[0-9][0-9AB][0-9]{3}$/.test(insee)) {
    return "missing_location";
  }
  const area = p.living_area_m2 === null ? NaN : Number(p.living_area_m2);
  if (!(area >= 9 && area <= 1000)) return "missing_area";
  if (!hasDvfCoverage(insee)) return "no_dvf_coverage";
  const land = dossier.parcelAreas.reduce<number>((sum, value) => sum + (value ?? 0), 0);
  return {
    type: p.property_type,
    lat: p.lat,
    lng: p.lng,
    insee,
    city: p.address_city,
    livingAreaM2: area,
    roomsCount: p.rooms_count,
    landM2: land > 0 ? land : null,
    constructionYear: p.construction_year,
    heatPumpYear: p.heat_pump_year,
    roofYear: p.roof_year,
    outdoorEquipment: p.outdoor_equipment ?? [],
    poolType: p.pool_type,
    noiseLevel: p.noise_level,
    overlooking: p.overlooking,
    assets: dossier.lifestyle.filter((i) => i.kind === "asset").map((i) => i.label),
    watchPoints: dossier.lifestyle.filter((i) => i.kind === "watch_point").map((i) => i.label),
  };
}
