// Fields the voice agent may fill, per tunnel step: the same `properties`
// columns, codes and rules as the screens (V4b, V6).

export type AgentStep = "technical" | "lifestyle";

export type PropertyType =
  | "maison"
  | "appartement"
  | "terrain"
  | "stationnement"
  | "dependance"
  | "local_commercial"
  | "immeuble"
  | "autre";

/** Property types the voice agent serves (V4 and V6), like the app's
 * `PropertyTypeProfile.voice` (parity fixture
 * tests/fixtures/property_type_profiles.json). The others (land, parking,
 * outbuilding, commercial premises, whole building) have a short screen
 * audit only. */
export const VOICE_TYPES: readonly PropertyType[] = ["maison", "appartement", "autre"];

/** Whether the voice agent serves [type] (null: not chosen yet, allowed). */
export function isVoiceType(type: string | null): boolean {
  return type === null || (VOICE_TYPES as readonly string[]).includes(type);
}

/** Which part of a property a field belongs to (V4b `asks…` getters). */
export type Scope =
  | "all" // asked for every property type
  | "building" // not for land
  | "whole_building" // houses and "autre" only
  | "heat_pump" // building with a heat pump
  | "pool"; // a pool among the outdoor equipment

export type FieldKind =
  | { type: "year"; min: number }
  | { type: "decimal"; min: number; max: number; exclusiveMin?: boolean }
  | { type: "int"; min: number; max: number }
  | { type: "enum"; codes: Record<string, string> }
  | { type: "list"; codes: Record<string, string> }
  | { type: "text"; max: number };

export interface FieldDef {
  column: string;
  /** French name (question topic, pending pill "Assainissement ?"). */
  label: string;
  kind: FieldKind;
  scope: Scope;
  /** Required for these property types (screen rules). */
  requiredFor?: PropertyType[];
}

const exposure = {
  nord: "Nord",
  nord_est: "Nord-Est",
  est: "Est",
  sud_est: "Sud-Est",
  sud: "Sud",
  sud_ouest: "Sud-Ouest",
  ouest: "Ouest",
  nord_ouest: "Nord-Ouest",
  traversant: "Traversant",
};

const levels = { plain_pied: "Plain-pied", r1: "R+1", r2_plus: "R+2 et plus" };

const wallMaterial = {
  parpaing: "Parpaing",
  brique: "Brique",
  pierre: "Pierre",
  beton: "Béton",
  moellon: "Moellon",
  bois: "Bois",
  pise: "Pisé",
};

const adjacency = {
  independant: "Indépendant",
  "1": "Mitoyen 1 côté",
  "2": "Mitoyen 2 côtés",
  "3": "Mitoyen 3 côtés",
};

const roofType = {
  tuiles: "Tuiles",
  ardoises: "Ardoises",
  toit_terrasse: "Toit-terrasse",
  bac_acier: "Bac acier",
  zinc: "Zinc",
  autre: "Autre",
};

const heatingSystems = {
  electricite: "Électrique",
  pac: "Pompe à chaleur",
  gaz: "Gaz",
  fioul: "Fioul",
  bois: "Poêle à bois",
  granules: "Poêle à granulés",
  cheminee: "Cheminée / insert",
  reseau_chaleur: "Réseau de chaleur",
  solaire: "Solaire",
  autre: "Autre",
};

const heatPumpType = {
  air_eau: "Air / eau",
  air_air: "Air / air",
  geothermique: "Géothermique",
};

const sanitation = {
  tout_a_l_egout: "Tout-à-l’égout",
  fosse_septique: "Fosse septique",
  puits_perdu: "Puits perdu",
};

const outdoorEquipment = {
  piscine: "Piscine",
  garage: "Garage",
  terrasse: "Terrasse",
  abri_jardin: "Abri de jardin",
  portail_motorise: "Portail motorisé",
};

const poolType = {
  enterree_liner: "Enterrée · liner",
  enterree_coque: "Enterrée · coque",
  enterree_beton: "Enterrée · béton",
  semi_enterree: "Semi-enterrée",
  hors_sol: "Hors-sol",
};

const overlooking = { aucun: "Aucun", leger: "Léger", important: "Important" };

export const TECHNICAL_FIELDS: FieldDef[] = [
  {
    column: "construction_year",
    label: "Construction",
    kind: { type: "year", min: 1600 },
    scope: "building",
    requiredFor: ["maison", "appartement", "autre"],
  },
  {
    column: "living_area_m2",
    label: "Surface habitable",
    kind: { type: "decimal", min: 5, max: 2000 },
    scope: "building",
    requiredFor: ["maison", "appartement", "autre"],
  },
  {
    column: "living_room_area_m2",
    label: "Surface séjour",
    kind: { type: "decimal", min: 1, max: 2000 },
    scope: "building",
  },
  {
    column: "rooms_count",
    label: "Pièces",
    kind: { type: "int", min: 1, max: 30 },
    scope: "building",
  },
  {
    column: "bedrooms_count",
    label: "Chambres",
    kind: { type: "int", min: 0, max: 30 },
    scope: "building",
  },
  {
    column: "levels",
    label: "Niveaux",
    kind: { type: "enum", codes: levels },
    scope: "whole_building",
    requiredFor: ["maison"],
  },
  {
    column: "orientation",
    label: "Exposition",
    kind: { type: "enum", codes: exposure },
    scope: "building",
  },
  {
    column: "wall_material",
    label: "Murs",
    kind: { type: "enum", codes: wallMaterial },
    scope: "building",
  },
  {
    column: "adjacency",
    label: "Mitoyenneté",
    kind: { type: "enum", codes: adjacency },
    scope: "whole_building",
  },
  {
    column: "roof_type",
    label: "Toiture",
    kind: { type: "enum", codes: roofType },
    scope: "whole_building",
  },
  {
    column: "roof_year",
    label: "Année toiture",
    kind: { type: "year", min: 1600 },
    scope: "whole_building",
  },
  {
    column: "heating_systems",
    label: "Chauffage",
    kind: { type: "list", codes: heatingSystems },
    scope: "building",
    requiredFor: ["maison", "appartement"],
  },
  {
    column: "heat_pump_type",
    label: "Type de PAC",
    kind: { type: "enum", codes: heatPumpType },
    scope: "heat_pump",
  },
  {
    column: "heat_pump_year",
    label: "Année PAC",
    kind: { type: "year", min: 1900 },
    scope: "heat_pump",
  },
  {
    column: "sanitation",
    label: "Assainissement",
    kind: { type: "enum", codes: sanitation },
    scope: "all",
  },
  {
    column: "outdoor_equipment",
    label: "Extérieur",
    kind: { type: "list", codes: outdoorEquipment },
    scope: "all",
  },
  {
    column: "pool_type",
    label: "Type de piscine",
    kind: { type: "enum", codes: poolType },
    scope: "pool",
  },
  {
    column: "pool_length_m",
    label: "Longueur piscine",
    kind: { type: "decimal", min: 0, max: 999.99, exclusiveMin: true },
    scope: "pool",
  },
  {
    column: "pool_width_m",
    label: "Largeur piscine",
    kind: { type: "decimal", min: 0, max: 999.99, exclusiveMin: true },
    scope: "pool",
  },
];

export const LIFESTYLE_FIELDS: FieldDef[] = [
  {
    column: "noise_level",
    label: "Bruit",
    kind: { type: "int", min: 1, max: 10 },
    scope: "all",
  },
  {
    column: "overlooking",
    label: "Vis-à-vis",
    kind: { type: "enum", codes: overlooking },
    scope: "all",
  },
  {
    column: "secret_note",
    label: "Note secrète",
    kind: { type: "text", max: 500 },
    scope: "all",
  },
];

/** Lifestyle item limits (`lifestyle_items` checks, V6 rules). */
export const LIFESTYLE_ITEM_MIN = 3;
export const LIFESTYLE_ITEM_MAX = 140;
export const LIFESTYLE_ITEMS_PER_KIND = 10;

export function stepFields(step: AgentStep): FieldDef[] {
  return step === "technical" ? TECHNICAL_FIELDS : LIFESTYLE_FIELDS;
}

export type PropertyValues = Record<string, unknown>;

/** Whether [field] is asked for this property (type and current answers,
 * e.g. pool fields only once a pool is known). */
export function isAsked(field: FieldDef, values: PropertyValues): boolean {
  const type = (values.property_type ?? null) as PropertyType | null;
  const building = type !== "terrain";
  switch (field.scope) {
    case "all":
      return true;
    case "building":
      return building;
    case "whole_building":
      return building && type !== "appartement";
    case "heat_pump":
      return building &&
        Array.isArray(values.heating_systems) &&
        values.heating_systems.includes("pac");
    case "pool":
      return Array.isArray(values.outdoor_equipment) &&
        values.outdoor_equipment.includes("piscine");
  }
}

function isEmpty(value: unknown): boolean {
  return value === null || value === undefined ||
    (Array.isArray(value) && value.length === 0) ||
    (typeof value === "string" && value.trim() === "");
}

/** The asked fields of [step] still without an answer, in question order. */
export function missingFields(
  step: AgentStep,
  values: PropertyValues,
): FieldDef[] {
  return stepFields(step).filter((field) =>
    isAsked(field, values) && isEmpty(values[field.column])
  );
}

/** The fields of [step] that can be asked for this property type,
 * including the conditional ones (heat pump, pool) not asked yet: the
 * seller may give them in the same sentence as their condition. */
export function promptFields(
  step: AgentStep,
  values: PropertyValues,
): FieldDef[] {
  const assumed = {
    ...values,
    heating_systems: ["pac"],
    outdoor_equipment: ["piscine"],
  };
  return stepFields(step).filter((field) => isAsked(field, assumed));
}

/** The condition of a conditional field, in French (prompt). */
export function conditionOf(field: FieldDef): string | null {
  switch (field.scope) {
    case "heat_pump":
      return "seulement s’il y a une pompe à chaleur";
    case "pool":
      return "seulement s’il y a une piscine";
    default:
      return null;
  }
}

export function fieldByColumn(
  step: AgentStep,
  column: string,
): FieldDef | undefined {
  return stepFields(step).find((field) => field.column === column);
}

/** The JSON Schema (strict structured output) of an agent answer. */
export function outputSchema(step: AgentStep): Record<string, unknown> {
  const columns = stepFields(step).map((field) => field.column);
  return {
    type: "object",
    additionalProperties: false,
    required: ["reply_fr", "answers", "lifestyle_items", "next_field", "done"],
    properties: {
      reply_fr: { type: "string" },
      answers: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["field", "value", "confidence", "quote"],
          properties: {
            field: { type: "string", enum: columns },
            value: { type: "string" },
            confidence: { type: "number" },
            quote: { type: "string" },
          },
        },
      },
      lifestyle_items: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["kind", "label", "quote"],
          properties: {
            kind: { type: "string", enum: ["asset", "watch_point"] },
            label: { type: "string" },
            quote: { type: "string" },
          },
        },
      },
      next_field: { type: "string", enum: [...columns, "none"] },
      done: { type: "boolean" },
    },
  };
}
