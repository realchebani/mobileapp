// Options the vision AI may propose (EPIC-15), with the JSON schemas of
// its structured outputs. The lists mirror the V5c form of the app (room
// suggestions, floor coverings, glazings, levels): parity fixture
// tests/fixtures/vision_options.json, read by the app tests too.

/** V5c room suggestions (`RoomSuggestion` names in the app). */
export const ROOM_KINDS = [
  "entrance",
  "livingRoom",
  "kitchen",
  "bedroom",
  "bathroom",
  "showerRoom",
  "toilet",
  "office",
  "hallway",
  "storeroom",
  "laundry",
  "garage",
  "basement",
  "other",
] as const;

/** Stored values of the V5c floor coverings (`FloorCovering.value`). */
export const FLOOR_COVERINGS = [
  "parquet_chene",
  "parquet",
  "carrelage",
  "moquette",
  "beton_cire",
  "stratifie",
  "vinyle",
  "autre",
] as const;

/** `rooms.glazing`. */
export const GLAZINGS = ["simple", "double", "triple"] as const;

/** `rooms.level`. */
export const LEVELS = ["sous_sol", "rdc", "etage_1", "etage_2", "combles"] as const;

/** Photo defects the model may report. */
export const QUALITY_ISSUES = [
  "dark",
  "overexposed",
  "blurry",
  "tilted",
  "cluttered",
] as const;

/** Unknown answer of an enumerated field (stored as null). */
export const UNKNOWN = "unknown";

const nullableEnum = (values: readonly string[]) => ({
  type: "string",
  enum: [...values, UNKNOWN],
});

// Lengths are enforced by validate.ts (maxItems is not supported by every
// provider in strict mode).
const stringList = { type: "array", items: { type: "string" } };

/** Structured output of vision-room (one photo of a room). */
export const ROOM_PHOTO_SCHEMA = {
  name: "room_photo_analysis",
  schema: {
    type: "object",
    additionalProperties: false,
    required: [
      "room_kind",
      "floor_covering",
      "glazing",
      "condition_notes",
      "personal_items",
      "people_visible",
      "quality_issues",
    ],
    properties: {
      room_kind: nullableEnum(ROOM_KINDS),
      floor_covering: nullableEnum(FLOOR_COVERINGS),
      glazing: nullableEnum(GLAZINGS),
      condition_notes: stringList,
      personal_items: stringList,
      people_visible: { type: "boolean" },
      quality_issues: {
        type: "array",
        items: { type: "string", enum: [...QUALITY_ISSUES] },
      },
    },
  },
};

/** Structured output of plan-reader (a photographed floor plan). */
export const PLAN_SCHEMA = {
  name: "floor_plan_reading",
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["is_floor_plan", "rooms", "printed_total_m2"],
    properties: {
      is_floor_plan: { type: "boolean" },
      rooms: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["name", "area_m2", "level", "kind"],
          properties: {
            name: { type: "string" },
            area_m2: { type: ["number", "null"] },
            level: nullableEnum(LEVELS),
            kind: nullableEnum(ROOM_KINDS),
          },
        },
      },
      printed_total_m2: { type: ["number", "null"] },
    },
  },
};
