// V5c dictation: the kinds of rooms (the app's `RoomSuggestion`), their
// names, and which existing room a sentence designates (plan §4.3). The
// app sends its table with short references (R1…R40); the model never
// sees an id.

import { hasStem, normalize } from "./anchors.ts";
import { numbersIn } from "./french_numbers.ts";

/** A row of the V5c table as sent by the app (draft included). */
export interface RoomRow {
  ref: string;
  name: string;
  level: string | null;
  area_m2: number;
  floor_covering: string | null;
  glazing: string | null;
  ceiling_height_m: number | null;
  is_annex: boolean;
}

export interface RoomKind {
  /** The app's `RoomSuggestion` name. */
  kind: string;
  /** French name given to a new room of this kind. */
  label: string;
  stems: readonly string[];
  /** Several rooms of this kind are numbered by the app ("Chambre 2"). */
  numbered?: boolean;
  /** Not part of the living area. */
  annex?: boolean;
}

export const ROOM_KINDS: readonly RoomKind[] = [
  { kind: "bathroom", label: "Salle de bain", stems: ["salle de bain", "salles de bain", "sdb"] },
  {
    kind: "showerRoom",
    label: "Salle d’eau",
    stems: ["salle d eau", "salles d eau", "salle de douche", "douche"],
  },
  {
    kind: "livingRoom",
    label: "Séjour",
    stems: ["sejour", "salon", "living", "piece de vie", "piece a vivre", "piece principale"],
  },
  { kind: "kitchen", label: "Cuisine", stems: ["cuisine", "kitchenette"] },
  {
    kind: "bedroom",
    label: "Chambre",
    stems: ["chambre", "suite parentale"],
    numbered: true,
  },
  { kind: "entrance", label: "Entrée", stems: ["entree", "hall"] },
  { kind: "toilet", label: "WC", stems: ["wc", "w c", "toilette"] },
  { kind: "office", label: "Bureau", stems: ["bureau"] },
  { kind: "hallway", label: "Dégagement", stems: ["degagement", "couloir", "palier"] },
  { kind: "storeroom", label: "Cellier", stems: ["cellier", "debarras", "reserve"], annex: true },
  { kind: "laundry", label: "Buanderie", stems: ["buanderie", "lingerie"], annex: true },
  { kind: "garage", label: "Garage", stems: ["garage"], annex: true },
  { kind: "basement", label: "Sous-sol", stems: ["sous sol", "cave"], annex: true },
];

/** The kind of a room named [name] (null: another kind of room). */
export function roomKindOf(name: string): RoomKind | null {
  for (const kind of ROOM_KINDS) {
    if (hasStem(name, kind.stems)) return kind;
  }
  return null;
}

const ORDINALS: Record<string, number> = {
  premiere: 1,
  premier: 1,
  "1re": 1,
  "1er": 1,
  deuxieme: 2,
  seconde: 2,
  second: 2,
  "2e": 2,
  "2eme": 2,
  troisieme: 3,
  "3e": 3,
  "3eme": 3,
  quatrieme: 4,
  "4e": 4,
  cinquieme: 5,
  "5e": 5,
  sixieme: 6,
  septieme: 7,
  huitieme: 8,
};

/** The numbers designating a room in [quote] ("la chambre 2", "la
 * deuxième chambre", "chambre numéro deux"). */
export function roomNumbersIn(quote: string): number[] {
  const words = normalize(quote).split(" ");
  const ordinals = words.filter((w) => w in ORDINALS).map((w) => ORDINALS[w]);
  return [...ordinals, ...numbersIn(quote).filter((n) => Number.isInteger(n) && n < 20)];
}

/** The number of a room named [name] ("Chambre 2" → 2, "Chambre" → 1). */
export function roomNumberOf(name: string): number {
  const match = /(\d+)\s*$/.exec(name.trim());
  return match ? Number(match[1]) : 1;
}

/** Words designating the room just dictated. */
const LAST_ROOM = ["derniere", "celle ci", "celle la", "cette piece", "la meme"];

/** Words announcing another room of a kind already listed. */
const ANOTHER = [
  "autre",
  "deuxieme",
  "seconde",
  "second",
  "nouvelle",
  "nouveau",
  "encore",
  "troisieme",
  "2e",
  "aussi une",
];

export type Designation =
  | { ok: true; room: RoomRow }
  | { ok: false; reason: "unknown_target" | "mismatch" }
  | { ok: false; reason: "ambiguous"; candidates: RoomRow[] };

/** Whether [quote] designates the room [ref] of [rooms] without
 * ambiguity; [lastRef] is the room dictated last ("la dernière"). */
export function designate(
  ref: string,
  quote: string,
  rooms: RoomRow[],
  lastRef: string | null,
): Designation {
  const room = rooms.find((r) => r.ref === ref);
  if (!room) return { ok: false, reason: "unknown_target" };
  if (ref === lastRef && hasStem(quote, LAST_ROOM)) return { ok: true, room };
  const kind = roomKindOf(room.name);
  const sameName = ` ${normalize(quote)} `.includes(` ${normalize(room.name)} `);
  if (!kind) return sameName ? { ok: true, room } : { ok: false, reason: "mismatch" };
  if (!hasStem(quote, kind.stems)) return { ok: false, reason: "mismatch" };
  const sameKind = rooms.filter((r) => roomKindOf(r.name)?.kind === kind.kind);
  if (sameKind.length === 1 || sameName) return { ok: true, room };
  const numbers = roomNumbersIn(quote);
  const byNumber = sameKind.filter((r) => numbers.includes(roomNumberOf(r.name)));
  if (byNumber.length === 1 && byNumber[0].ref === ref) return { ok: true, room };
  if (byNumber.length === 1) return { ok: false, reason: "mismatch" };
  return { ok: false, reason: "ambiguous", candidates: sameKind };
}

/** The existing room a "new" room of [kind] would duplicate (a kind
 * listed once, not numbered, and no "autre" / "deuxième" in [quote]);
 * several such rooms are ambiguous. */
export function duplicateOf(
  kind: RoomKind | null,
  quote: string,
  rooms: RoomRow[],
): RoomRow[] {
  if (!kind || kind.numbered || hasStem(quote, ANOTHER)) return [];
  return rooms.filter((r) => roomKindOf(r.name)?.kind === kind.kind);
}

/** "Séjour · RDC · 38 m²" (prompt and pills; descriptions are never sent
 * back to the model). */
export function roomSummary(
  room: Pick<RoomRow, "name" | "level" | "area_m2">,
  levels: Record<string, string>,
  area: (value: number) => string,
): string {
  return [
    room.name,
    room.level ? levels[room.level] ?? room.level : null,
    `${area(room.area_m2)} m²`,
  ]
    .filter((part) => part !== null).join(" · ");
}
