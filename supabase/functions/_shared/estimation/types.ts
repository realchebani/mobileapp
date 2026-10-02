// Shared types of the non-certified estimate (EPIC-05).

export type PropertyType = "maison" | "appartement";

/** DVF type of a cached sale: a dwelling, or one outbuilding alone
 * (garage, parking, box, cave… : DVF « Dépendance »). */
export type DvfType = PropertyType | "dependance";

/** A cleaned DVF sale of one outbuilding alone in its mutation (EPIC-13):
 * priced per unit, DVF has no surface for most of them. */
export interface OutbuildingSale {
  idMutation: string;
  insee: string;
  year: number;
  /** ISO date `YYYY-MM-DD`. */
  soldOn: string;
  priceEur: number;
  /** Street name (adresse_nom_voie), never the house number. */
  street: string | null;
  lat: number | null;
  lng: number | null;
}

/** A garage / parking (stationnement) or an outbuilding (dependance) to
 * estimate from the sales of single outbuildings. */
export interface OutbuildingSubject {
  type: "dependance";
  /** The `property_type` of the dossier. */
  kind: "stationnement" | "dependance";
  lat: number;
  lng: number;
  insee: string;
  city: string | null;
}

/** A cleaned DVF sale: one dwelling sold in one mutation. */
export interface DvfSale {
  idMutation: string;
  insee: string;
  year: number;
  /** ISO date `YYYY-MM-DD`. */
  soldOn: string;
  type: PropertyType;
  priceEur: number;
  areaM2: number;
  rooms: number | null;
  landM2: number | null;
  /** Street name (adresse_nom_voie), never the house number. */
  street: string | null;
  lat: number | null;
  lng: number | null;
}

/** The property to estimate (only what the method needs, no personal data). */
export interface Subject {
  type: PropertyType;
  lat: number;
  lng: number;
  insee: string;
  city: string | null;
  livingAreaM2: number;
  roomsCount: number | null;
  landM2: number | null;
  constructionYear: number | null;
  heatPumpYear: number | null;
  roofYear: number | null;
  outdoorEquipment: string[];
  poolType: string | null;
  noiseLevel: number | null;
  overlooking: string | null;
  assets: string[];
  watchPoints: string[];
}

/** Median €/m² of one half-year. */
export interface SemesterPoint {
  /** `YYYY-S1` (January–June) or `YYYY-S2`. */
  semester: string;
  medianM2: number;
  /** Smoothed value (rolling median of 3 half-years), used as index. */
  indexM2: number;
  count: number;
  scale: "commune" | "epci" | "departement";
}

export interface Comparable {
  type: DvfType;
  /** Street name, or null when the street has fewer than 3 sales. */
  street: string | null;
  /** Null for an outbuilding (priced per unit). */
  area_m2: number | null;
  rooms: number | null;
  land_m2: number | null;
  /** Year of the sale only (owner decision: no month, for discretion). */
  sold_year: number;
  /** Distance rounded to 100 m; null when unknown. */
  distance_m: number | null;
  price_eur: number;
  /** Null for an outbuilding. */
  price_m2_eur: number | null;
  price_m2_today_eur: number | null;
  weight: number;
}

export interface Factor {
  sign: "+" | "-";
  label: string;
}

export type InsufficientReason =
  | "too_few_sales"
  | "unsupported_type"
  | "missing_area"
  | "missing_location"
  | "no_dvf_coverage";

/** Deterministic result of the method (before the AI explanation). */
export interface EstimateResult {
  status: "ok" | "insufficient";
  reason: InsufficientReason | null;
  dataUntil: string | null;
  lowEur: number | null;
  medianEur: number | null;
  highEur: number | null;
  priceM2Low: number | null;
  priceM2Median: number | null;
  priceM2High: number | null;
  confidence: number | null;
  comparablesCount: number;
  scope: "radius" | "commune" | null;
  radiusM: number | null;
  months: number | null;
  sales12m: number | null;
  yoyChangePct: number | null;
  semesterMedians: SemesterPoint[];
  comparables: Comparable[];
  factors: Factor[];
}

export const METHOD_VERSION = "dvf-v1";

/** Method of the outbuilding estimate (median of single outbuilding sales). */
export const OUTBUILDING_METHOD_VERSION = "dvf-dependance-v1";
