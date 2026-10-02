// Validation of the vision AI outputs (EPIC-15). The AI classifies and
// reads; it never measures: a room photo analysis carries no number at all
// (a condition note with a digit is dropped), and a plan reading only keeps
// the areas printed on the plan, within plausible bounds.

import {
  FLOOR_COVERINGS,
  GLAZINGS,
  LEVELS,
  QUALITY_ISSUES,
  ROOM_KINDS,
  UNKNOWN,
} from "./schema.ts";

/** What vision-room stores in `room_photos.analysis` (version 1). */
export interface RoomPhotoAnalysis {
  version: 1;
  room_kind: string | null;
  floor_covering: string | null;
  glazing: string | null;
  condition_notes: string[];
  personal_items: string[];
  people_visible: boolean;
  quality_issues: string[];
  model: string;
  analyzed_at: string;
}

export interface PlanRoom {
  name: string;
  area_m2: number | null;
  level: string | null;
  kind: string | null;
}

/** What plan-reader stores in `property_documents.extracted.plan_reading`. */
export interface PlanReading {
  version: 1;
  is_floor_plan: boolean;
  rooms: PlanRoom[];
  printed_total_m2: number | null;
  /** Sum of the areas read (m², 2 decimals). */
  rooms_total_m2: number;
  /** Whether the sum matches the printed total (±5 %); null without total. */
  total_matches: boolean | null;
  model: string;
  read_at: string;
}

/** Limits of the outputs. */
export const OUTPUT_LIMITS = {
  conditionNotes: 4,
  conditionNoteChars: 120,
  personalItems: 6,
  personalItemChars: 60,
  planRooms: 40,
  roomNameChars: 40,
  minRoomArea: 0.5,
  maxRoomArea: 1000,
  maxTotalArea: 100_000,
  /** Accepted gap between the sum of the rooms and the printed total. */
  totalTolerance: 0.05,
};

/** The model's answer could not be used. */
export class InvalidOutput extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidOutput";
  }
}

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new InvalidOutput("not an object");
  }
  return value as Record<string, unknown>;
}

function parse(content: string): Record<string, unknown> {
  try {
    return record(JSON.parse(content));
  } catch (error) {
    if (error instanceof InvalidOutput) throw error;
    throw new InvalidOutput("not JSON");
  }
}

function oneOf(value: unknown, values: readonly string[]): string | null {
  return typeof value === "string" && value !== UNKNOWN && values.includes(value) ? value : null;
}

/** Trimmed distinct texts of [value] (2 to [maxChars] characters), at most
 * [maxItems]; [keep] filters them further. */
function texts(
  value: unknown,
  maxItems: number,
  maxChars: number,
  keep: (text: string) => boolean = () => true,
): string[] {
  if (!Array.isArray(value)) return [];
  const result: string[] = [];
  for (const raw of value) {
    if (typeof raw !== "string") continue;
    const text = raw.replace(/\s+/g, " ").trim();
    if (text.length < 2 || text.length > maxChars || !keep(text)) continue;
    if (result.some((t) => t.toLowerCase() === text.toLowerCase())) continue;
    result.push(text);
    if (result.length === maxItems) break;
  }
  return result;
}

/** Words of a measurement or of a number written in letters: a note
 * carrying one is dropped (the AI never gives a figure). */
const MEASUREMENT_WORDS =
  /(?<![\p{L}\p{N}])(m²|m2|mètres?|metres?|centimètres?|cm|mm|surfaces?|superficies?|hauteurs?|longueurs?|largeurs?|dimensions?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|treize|quatorze|quinze|seize|vingts?|trente|quarante|cinquante|soixante|cents?|mille)(?![\p{L}\p{N}])/iu;

/** No figure at all in a note (no surface, no dimension, no count, also
 * in letters). */
const hasNoDigit = (text: string) => !/\d/.test(text) && !MEASUREMENT_WORDS.test(text);

/** A room name of a plan: letters, digits, spaces, apostrophes and
 * hyphens only, at most [OUTPUT_LIMITS.roomNameChars] characters. */
function roomName(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replace(/[^\p{L}\p{N} '’-]/gu, " ").replace(/\s+/g, " ").trim()
    .slice(0, OUTPUT_LIMITS.roomNameChars).trim();
}

/** The analysis of a room photo from the model's [content]. */
export function validateRoomAnalysis(
  content: string,
  model: string,
  now: Date,
): RoomPhotoAnalysis {
  const raw = parse(content);
  if (typeof raw.people_visible !== "boolean") {
    throw new InvalidOutput("people_visible missing");
  }
  const issues = Array.isArray(raw.quality_issues)
    ? QUALITY_ISSUES.filter((issue) => (raw.quality_issues as unknown[]).includes(issue))
    : [];
  return {
    version: 1,
    room_kind: oneOf(raw.room_kind, ROOM_KINDS),
    floor_covering: oneOf(raw.floor_covering, FLOOR_COVERINGS),
    glazing: oneOf(raw.glazing, GLAZINGS),
    condition_notes: texts(
      raw.condition_notes,
      OUTPUT_LIMITS.conditionNotes,
      OUTPUT_LIMITS.conditionNoteChars,
      hasNoDigit,
    ),
    personal_items: texts(
      raw.personal_items,
      OUTPUT_LIMITS.personalItems,
      OUTPUT_LIMITS.personalItemChars,
      hasNoDigit,
    ),
    people_visible: raw.people_visible,
    quality_issues: [...issues],
    model,
    analyzed_at: now.toISOString(),
  };
}

function area(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  if (value < min || value > max) return null;
  return Math.round(value * 100) / 100;
}

/** The reading of a floor plan from the model's [content]. */
export function validatePlanReading(
  content: string,
  model: string,
  now: Date,
): PlanReading {
  const raw = parse(content);
  if (typeof raw.is_floor_plan !== "boolean" || !Array.isArray(raw.rooms)) {
    throw new InvalidOutput("plan fields missing");
  }
  const rooms: PlanRoom[] = [];
  if (raw.is_floor_plan) {
    for (const item of raw.rooms) {
      if (typeof item !== "object" || item === null) continue;
      const room = item as Record<string, unknown>;
      const name = roomName(room.name);
      if (!name) continue;
      rooms.push({
        name,
        area_m2: area(room.area_m2, OUTPUT_LIMITS.minRoomArea, OUTPUT_LIMITS.maxRoomArea),
        level: oneOf(room.level, LEVELS),
        kind: oneOf(room.kind, ROOM_KINDS),
      });
      if (rooms.length === OUTPUT_LIMITS.planRooms) break;
    }
  }
  const printed = raw.is_floor_plan
    ? area(raw.printed_total_m2, 1, OUTPUT_LIMITS.maxTotalArea)
    : null;
  const total = Math.round(
    rooms.reduce((sum, room) => sum + (room.area_m2 ?? 0), 0) * 100,
  ) / 100;
  return {
    version: 1,
    is_floor_plan: raw.is_floor_plan,
    rooms,
    printed_total_m2: printed,
    rooms_total_m2: total,
    total_matches: printed === null
      ? null
      : Math.abs(total - printed) <= printed * OUTPUT_LIMITS.totalTolerance,
    model,
    read_at: now.toISOString(),
  };
}
