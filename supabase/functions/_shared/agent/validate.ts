// Server-side validation of the agent's answers: whitelisted fields and
// codes, screen rules (bounds, consistency), literal quotes, numeric and
// lexical anchors, free texts covered by what was said, confidence, and
// the changes that need the seller's confirmation (plan §4.2, §5.3).
// Nothing the model says reaches the dossier without passing here, and the
// app then writes it itself (RLS, lock).

import {
  isPersonName,
  lexicalAnchor,
  normalize,
  numericAnchor,
  quoteFound,
  textCovered,
} from "./anchors.ts";
import { VOICE_DEFAULTS } from "./defaults.ts";
import { designate, duplicateOf, roomKindOf, type RoomRow } from "./rooms.ts";
import {
  type AgentStep,
  codesOf,
  type EntityDef,
  type FieldDef,
  isAsked,
  STEP_LABELS,
  stepOfColumn,
  stepSchema,
} from "./steps/index.ts";
import {
  LIFESTYLE_ITEM_MAX,
  LIFESTYLE_ITEM_MIN,
  LIFESTYLE_ITEMS_PER_KIND,
} from "./steps/lifestyle.ts";
import { PROPERTY_TYPE_LABELS } from "./steps/context.ts";
import { FLOOR_COVERINGS, GLAZINGS, ROOM_LEVELS } from "./steps/rooms.ts";

export { normalize, quoteFound };

export const MIN_CONFIDENCE = 0.7;

/** Most entity operations taken from one turn. */
export const MAX_ENTITY_OPS = 12;

/** Most habitable area of the rooms of a dossier (m², V4b bound). */
export const MAX_LIVING_AREA = 2000;

export interface ModelAnswer {
  field: string;
  value: string;
  confidence: number;
  quote: string;
  /** The seller corrects a value of the previous turn. */
  correction?: boolean;
}

export interface ModelEntityField {
  field: string;
  value: string;
  confidence: number;
  quote: string;
}

export interface ModelEntityOp {
  entity: string;
  op: string;
  /** "new" or a short reference of the prompt (R1, E2…). */
  target: string;
  /** The words designating the existing entity. */
  target_quote: string;
  correction?: boolean;
  fields: ModelEntityField[];
  copy_from?: string;
  copy_fields?: string[];
  copy_quote?: string;
}

export interface ModelLifestyleItem {
  kind: string;
  label: string;
  quote: string;
}

export interface ModelOutput {
  reply_fr: string;
  answers: ModelAnswer[];
  entity_ops?: ModelEntityOp[];
  lifestyle_items: ModelLifestyleItem[];
  out_of_step?: string[];
  next_field: string;
  done: boolean;
}

export interface Pill {
  field: string;
  label_fr: string;
}

/** An applied answer: [changed_fr] when it replaces a known value
 * ("Modifié : 1998 → 1999"), [corrected] when the seller corrected it. */
export interface Fact extends Pill {
  changed_fr?: string;
  corrected?: boolean;
}

export type RejectionReason =
  | "unknown_field"
  | "not_asked"
  | "invalid_value"
  | "out_of_range"
  | "inconsistent"
  | "quote_not_found"
  | "low_confidence"
  | "duplicate"
  | "full"
  | "number_not_in_quote"
  | "anchor_missing"
  | "not_covered"
  | "unknown_target"
  | "mismatch"
  | "ambiguous"
  | "not_allowed";

export interface Rejection {
  field: string;
  value: string;
  reason: RejectionReason;
}

/** A change of an entity, applied by the app to its form: a room, a
 * previous estimate or a co-owner. */
export interface EntityChange {
  entity: string;
  op: "create" | "update" | "delete";
  /** "new", or the reference of the existing entity (R1, E2…). */
  target: string;
  /** Validated values, as stored (room kind in `kind`). */
  values: Record<string, unknown>;
  label_fr: string;
  /** "Modifiée : 38 → 40 m²". */
  changed_fr?: string;
  corrected?: boolean;
}

export type ConfirmationReason =
  | "type_change"
  | "delete"
  | "co_owner"
  | "medium_confidence"
  | "strong_change"
  | "clear_situations"
  | "merge_room";

/** A change applied only once the seller says or taps "Oui". */
export interface Confirmation {
  id: string;
  reason: ConfirmationReason;
  /** "Type : garage ?". */
  label_fr: string;
  patch: Record<string, unknown>;
  entity_ops: EntityChange[];
}

/** An answer about another step: never written, the agent says where it
 * will be asked. */
export interface OutOfStep {
  field: string;
  step: AgentStep;
  label_fr: string;
}

export interface ValidatedTurn {
  patch: Record<string, unknown>;
  facts: Fact[];
  pending: Pill[];
  lifestyle_items: { kind: "asset" | "watch_point"; label: string }[];
  suggestions: Record<string, string>;
  rejected: Rejection[];
  entity_ops: EntityChange[];
  confirmations: Confirmation[];
  out_of_step: OutOfStep[];
  /** Columns (or "room:R3"…) the seller corrected in this turn. */
  corrections: string[];
}

/** A previous estimate as sent by the app (V3 cards). */
export interface EstimateRow {
  ref: string;
  price_eur: number | null;
  estimated_month: string | null;
  agency_name: string | null;
}

export interface ValidationContext {
  step: AgentStep;
  /** Current values: the dossier, overridden by the screen's draft. */
  values: Record<string, unknown>;
  transcript: string;
  currentYear: number;
  /** 1–12 (months of previous estimates cannot be in the future). */
  currentMonth?: number;
  /** Labels already listed on V6 (saved or drafted), per kind. */
  lifestyleLabels?: { asset: string[]; watch_point: string[] };
  /** The step sheet can ask confirmations (the V4 "Night" audit cannot:
   * risky answers are asked again instead). */
  interactive?: boolean;
  /** V5c table (draft included). */
  rooms?: RoomRow[];
  /** The room dictated last ("la dernière"). */
  lastRoomRef?: string | null;
  /** V3 estimate cards. */
  estimates?: EstimateRow[];
  /** V1 co-owners already listed. */
  coOwnersCount?: number;
}

const NBSP = "\u00a0";

/** [value] the French way: "38,5", "320 000". */
export function formatNumber(value: number): string {
  const rounded = Math.round(value * 100) / 100;
  const [whole, decimals] = String(rounded).split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, NBSP);
  return decimals ? `${grouped},${decimals}` : grouped;
}

/** French typography of a label: a no-break space before ? ! : ; and
 * before a unit (m², m, €). */
export function typo(text: string): string {
  return text
    .replace(/ ([?!:;])/g, `${NBSP}$1`)
    .replace(/(\d) (m²|m|€)(?=$|[\s·,)?])/g, `$1${NBSP}$2`);
}

function lowerFirst(text: string): string {
  return text.charAt(0).toLowerCase() + text.slice(1);
}

function upperFirst(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

function shorten(text: string, max = 40): string {
  return text.length <= max ? text : `${text.slice(0, max - 1).trimEnd()}…`;
}

type Parsed = { ok: true; value: unknown; dimensions?: [number, number] } | {
  ok: false;
  reason: RejectionReason;
};

function parseNumber(raw: string): number | null {
  const compact = raw.replace(/\s|\u00a0|\u202f/g, "").replace(",", ".")
    .replace(/m²|m2|m$|€$/i, "");
  return /^\d+(\.\d+)?$/.test(compact) ? Number(compact) : null;
}

const DIMENSIONS = /^(\d+(?:[.,]\d+)?)\s*(?:x|×|\*|sur|par)\s*(\d+(?:[.,]\d+)?)\s*(?:m)?$/i;

function parseValue(
  field: FieldDef,
  raw: string,
  context: { year: number; month: number; values: Record<string, unknown> },
): Parsed {
  const kind = field.kind;
  const text = raw.trim();
  switch (kind.type) {
    case "year": {
      if (!/^\d{4}$/.test(text)) return { ok: false, reason: "invalid_value" };
      const value = Number(text);
      return value < kind.min || value > context.year
        ? { ok: false, reason: "out_of_range" }
        : { ok: true, value };
    }
    case "decimal": {
      const value = parseNumber(text);
      if (value === null) return { ok: false, reason: "invalid_value" };
      const tooSmall = kind.exclusiveMin ? value <= kind.min : value < kind.min;
      return tooSmall || value > kind.max
        ? { ok: false, reason: "out_of_range" }
        : { ok: true, value: Math.round(value * 100) / 100 };
    }
    case "area": {
      const dims = DIMENSIONS.exec(text);
      if (dims && VOICE_DEFAULTS.areaFromDimensions) {
        const a = Number(dims[1].replace(",", "."));
        const b = Number(dims[2].replace(",", "."));
        const value = Math.round(a * b * 100) / 100;
        return value < kind.min || value > kind.max
          ? { ok: false, reason: "out_of_range" }
          : { ok: true, value, dimensions: [a, b] };
      }
      const value = parseNumber(text);
      if (value === null) return { ok: false, reason: "invalid_value" };
      return value < kind.min || value > kind.max
        ? { ok: false, reason: "out_of_range" }
        : { ok: true, value: Math.round(value * 100) / 100 };
    }
    case "int": {
      if (!/^\d+$/.test(text)) return { ok: false, reason: "invalid_value" };
      const value = Number(text);
      return value < kind.min || value > kind.max
        ? { ok: false, reason: "out_of_range" }
        : { ok: true, value };
    }
    case "money": {
      const compact = text.replace(/[\s\u00a0\u202f€]/g, "").replace(/euros?$/i, "");
      if (!/^\d+$/.test(compact)) return { ok: false, reason: "invalid_value" };
      const value = Number(compact);
      return value < kind.min || value > kind.max
        ? { ok: false, reason: "out_of_range" }
        : { ok: true, value };
    }
    case "month": {
      const m = /^(\d{1,2})\/(\d{4})$/.exec(text) ?? /^(\d{4})-(\d{1,2})(?:-\d{1,2})?$/.exec(text);
      if (!m) return { ok: false, reason: "invalid_value" };
      const [year, month] = m[0].includes("/")
        ? [Number(m[2]), Number(m[1])]
        : [Number(m[1]), Number(m[2])];
      if (month < 1 || month > 12) return { ok: false, reason: "invalid_value" };
      if (
        year < kind.minYear || year > context.year ||
        (year === context.year && month > context.month)
      ) {
        return { ok: false, reason: "out_of_range" };
      }
      return { ok: true, value: `${year}-${String(month).padStart(2, "0")}-01` };
    }
    case "bool": {
      const t = normalize(text);
      if (["true", "oui", "vrai"].includes(t)) return { ok: true, value: true };
      if (["false", "non", "faux"].includes(t)) return { ok: true, value: false };
      return { ok: false, reason: "invalid_value" };
    }
    case "enum":
      return text in codesOf(field, context.values)
        ? { ok: true, value: text }
        : { ok: false, reason: "invalid_value" };
    case "list": {
      const offered = codesOf(field, context.values);
      const codes = text.split(/[,;]/).map((code) => code.trim())
        .filter((code) => code.length > 0);
      if (codes.length === 0 || codes.some((code) => !(code in offered))) {
        return { ok: false, reason: "invalid_value" };
      }
      return { ok: true, value: codes };
    }
    case "text": {
      const value = text.replace(/\s+/g, " ").slice(0, kind.max).trim();
      return value.length === 0 ? { ok: false, reason: "invalid_value" } : { ok: true, value };
    }
  }
}

/** Whether the quote backs the value: numbers said, keywords of the
 * codes, free text covered by the transcript. */
function anchored(
  field: FieldDef,
  parsed: Parsed & { ok: true },
  quote: string,
  transcript: string,
): RejectionReason | null {
  const kind = field.kind;
  switch (kind.type) {
    case "year":
    case "decimal":
    case "int":
    case "money":
      if (field.numericAnchor === false) return null;
      return numericAnchor(parsed.value as number, quote) ? null : "number_not_in_quote";
    case "area": {
      const numbers = parsed.dimensions ?? [parsed.value as number];
      return numbers.every((n) => numericAnchor(n, quote)) ? null : "number_not_in_quote";
    }
    case "month": {
      const year = Number(String(parsed.value).slice(0, 4));
      return numericAnchor(year, quote) ? null : "number_not_in_quote";
    }
    case "bool":
      return lexicalAnchor(field.anchors, [], quote) ? null : "anchor_missing";
    case "enum":
      return lexicalAnchor(field.anchors, [parsed.value as string], quote)
        ? null
        : "anchor_missing";
    case "list":
      return lexicalAnchor(field.anchors, parsed.value as string[], quote)
        ? null
        : "anchor_missing";
    case "text":
      if (kind.suggestion) return null;
      if (kind.coverage) {
        return textCovered(parsed.value as string, transcript) ? null : "not_covered";
      }
      return null;
  }
}

/** The value of [field] in French ("1998", "Tuiles", "320 000 €"). */
export function valueText(field: FieldDef, value: unknown): string {
  const kind = field.kind;
  switch (kind.type) {
    case "year":
    case "int":
      return String(value);
    case "decimal":
    case "area":
      return field.column.startsWith("pool_") || field.column === "ceiling_height_m"
        ? `${formatNumber(value as number)} m`
        : `${formatNumber(value as number)} m²`;
    case "money":
      return `${formatNumber(value as number)} €`;
    case "month": {
      const [year, month] = String(value).split("-");
      return `${month}/${year}`;
    }
    case "bool":
      return value ? "oui" : "non";
    case "enum":
      return kind.codes[value as string] ?? String(value);
    case "list":
      return (value as string[]).map((code) => kind.codes[code] ?? code).join(", ");
    case "text":
      return shorten(String(value));
  }
}

/** The French pill of an accepted answer ("Construction 1998"). */
export function factLabel(field: FieldDef, value: unknown): string {
  return typo(rawFactLabel(field, value));
}

function rawFactLabel(field: FieldDef, value: unknown): string {
  const kind = field.kind;
  switch (kind.type) {
    case "year":
    case "money":
      return `${field.label} ${valueText(field, value)}`;
    case "decimal":
    case "area":
      return `${field.label} ${valueText(field, value)}`;
    case "int":
      return field.column === "noise_level"
        ? `${field.label} ${value}/10`
        : field.column === "units_count"
        ? `${value} logements`
        : `${value} ${lowerFirst(field.label)}`;
    case "month":
      return `${field.label} ${valueText(field, value)}`;
    case "bool":
      return `${field.label} : ${valueText(field, value)}`;
    case "enum": {
      const label = kind.codes[value as string];
      if (field.column === "wall_material") return label;
      if (field.column === "property_type") return `Type : ${lowerFirst(label)}`;
      if (field.column === "ownership_type") return label;
      return `${field.label} ${lowerFirst(label)}`;
    }
    case "list":
      return valueText(field, value);
    case "text":
      return kind.suggestion ? field.label : `${field.label} : ${valueText(field, value)}`;
  }
}

function isEmpty(value: unknown): boolean {
  return value === null || value === undefined || value === "" ||
    (Array.isArray(value) && value.length === 0);
}

function sameValue(a: unknown, b: unknown): boolean {
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((item) => b.includes(item));
  }
  if (typeof a === "number" && typeof b === "number") return Math.abs(a - b) < 0.005;
  return a === b;
}

/** Whether replacing [previous] by [value] is a strong change (plan
 * §5.3): an area off by more than half, a year by more than 20 years. */
function isStrongChange(field: FieldDef, previous: unknown, value: unknown): boolean {
  if (typeof previous !== "number" || typeof value !== "number") return false;
  const { ratio, years } = VOICE_DEFAULTS.strongChange;
  switch (field.kind.type) {
    case "year":
      return Math.abs(value - previous) > years;
    case "decimal":
    case "area":
    case "money":
      return previous > 0 && Math.abs(value - previous) / previous > ratio;
    default:
      return false;
  }
}

interface Accepted {
  field: FieldDef;
  value: unknown;
  previous: unknown;
  corrected: boolean;
  medium: boolean;
}

/** Validates a model answer for [context]: see [ValidatedTurn]. */
export function validateTurn(output: ModelOutput, context: ValidationContext): ValidatedTurn {
  const { step, values, transcript, currentYear } = context;
  const schema = stepSchema(step);
  const interactive = context.interactive === true;
  const parseContext = { year: currentYear, month: context.currentMonth ?? 12, values };
  const result: ValidatedTurn = {
    patch: {},
    facts: [],
    pending: [],
    lifestyle_items: [],
    suggestions: {},
    rejected: [],
    entity_ops: [],
    confirmations: [],
    out_of_step: [],
    corrections: [],
  };
  const merged: Record<string, unknown> = { ...values };
  const accepted: Accepted[] = [];
  const pendingColumns = new Set<string>();
  const fieldOf = (column: string) => schema.fields.find((f) => f.column === column);

  const reject = (field: string, value: string, reason: RejectionReason) =>
    result.rejected.push({ field, value, reason });

  // A new property type decides which fields are asked: it goes first,
  // then the lists (heat pump, pool).
  const rank = (answer: ModelAnswer) => {
    if (answer.field === "property_type") return 0;
    return fieldOf(answer.field)?.kind.type === "list" ? 1 : 2;
  };
  const answers = [...output.answers].sort((a, b) => rank(a) - rank(b));

  for (const answer of answers) {
    const field = fieldOf(answer.field);
    if (!field) {
      reject(answer.field, answer.value, "unknown_field");
      continue;
    }
    if (!quoteFound(answer.quote, transcript)) {
      reject(answer.field, answer.value, "quote_not_found");
      continue;
    }
    if (!isAsked(field, merged)) {
      reject(answer.field, answer.value, "not_asked");
      continue;
    }
    const medium = answer.confidence >= VOICE_DEFAULTS.confirmFrom &&
      answer.confidence < MIN_CONFIDENCE;
    if (!(answer.confidence >= MIN_CONFIDENCE) && !(medium && interactive)) {
      reject(answer.field, answer.value, "low_confidence");
      pendingColumns.add(field.column);
      continue;
    }
    const parsed = parseValue(field, answer.value, parseContext);
    if (!parsed.ok) {
      reject(answer.field, answer.value, parsed.reason);
      pendingColumns.add(field.column);
      continue;
    }
    const weak = anchored(field, parsed, answer.quote, transcript);
    if (weak) {
      reject(answer.field, answer.value, weak);
      pendingColumns.add(field.column);
      continue;
    }
    let value = parsed.value;
    if (field.kind.type === "list") {
      const existing = Array.isArray(merged[field.column]) ? merged[field.column] as string[] : [];
      const said = value as string[];
      const exclusive = field.kind.exclusive;
      const union = exclusive && said.includes(exclusive)
        ? [exclusive]
        : [...existing.filter((code) => code !== exclusive), ...said];
      value = Object.keys(field.kind.codes).filter((code) => union.includes(code));
    }
    accepted.push({
      field,
      value,
      previous: merged[field.column],
      corrected: answer.correction === true,
      medium,
    });
    merged[field.column] = value;
  }

  // Cross-field rules, on the dossier as it would be after this turn.
  const num = (column: string) =>
    typeof merged[column] === "number" ? merged[column] as number : null;
  const consistent = (field: FieldDef, value: unknown): boolean => {
    const v = value as number;
    switch (field.column) {
      case "roof_year": {
        const built = num("construction_year");
        return built === null || v >= built;
      }
      case "construction_year": {
        const roof = num("roof_year");
        return roof === null || roof >= v;
      }
      case "living_room_area_m2": {
        const living = num("living_area_m2");
        return living === null || v <= living;
      }
      case "living_area_m2": {
        const room = num("living_room_area_m2");
        return room === null || room <= v;
      }
      case "bedrooms_count": {
        const rooms = num("rooms_count");
        return rooms === null || v <= rooms;
      }
      case "rooms_count": {
        const bedrooms = num("bedrooms_count");
        return bedrooms === null || bedrooms <= v;
      }
      default:
        return true;
    }
  };

  const typeAnswer = accepted.find((a) => a.field.column === "property_type");
  const typeChange = typeAnswer !== undefined && !isEmpty(typeAnswer.previous) &&
    typeAnswer.previous !== typeAnswer.value;
  const typeConfirmation: Confirmation | null = typeChange && interactive
    ? {
      id: "",
      reason: "type_change",
      label_fr: `Type : ${lowerFirst(PROPERTY_TYPE_LABELS[typeAnswer!.value as string])} ?`,
      patch: {},
      entity_ops: [],
    }
    : null;

  for (const item of accepted) {
    const { field, value, previous } = item;
    if (!consistent(field, value)) {
      reject(field.column, String(value), "inconsistent");
      pendingColumns.add(field.column);
      continue;
    }
    if (field.kind.type === "text" && field.kind.suggestion) {
      result.suggestions[field.column] = value as string;
      continue;
    }
    // A type change is confirmed, with the answers it makes asked.
    if (typeChange) {
      if (!typeConfirmation) {
        if (field.column === "property_type" || !isAsked(field, values)) {
          reject(field.column, String(value), "not_allowed");
          pendingColumns.add(field.column);
          continue;
        }
      } else if (field.column === "property_type" || !isAsked(field, values)) {
        typeConfirmation.patch[field.column] = value;
        continue;
      }
    }
    const replaces = !isEmpty(previous) && !sameValue(previous, value);
    const exclusive = field.kind.type === "list" ? field.kind.exclusive : undefined;
    // "Aucune" said while other situations are ticked.
    const clearsOthers = exclusive !== undefined && (value as string[]).includes(exclusive) &&
      Array.isArray(previous) && previous.some((code) => code !== exclusive);
    const confirmReason: ConfirmationReason | null = !interactive
      ? null
      : item.medium
      ? "medium_confidence"
      : clearsOthers
      ? "clear_situations"
      : replaces && isStrongChange(field, previous, value)
      ? "strong_change"
      : null;
    if (confirmReason) {
      result.confirmations.push({
        id: "",
        reason: confirmReason,
        label_fr: replaces
          ? `${field.label} : ${valueText(field, previous)} → ${valueText(field, value)} ?`
          : `${factLabel(field, value)} ?`,
        patch: { [field.column]: value },
        entity_ops: [],
      });
      continue;
    }
    result.patch[field.column] = value;
    const fact: Fact = {
      field: field.column,
      label_fr: item.corrected ? `${factLabel(field, value)} (corrigé)` : factLabel(field, value),
    };
    if (replaces) {
      fact.changed_fr = `Modifié : ${valueText(field, previous)} → ${valueText(field, value)}`;
    }
    if (item.corrected) {
      fact.corrected = true;
      result.corrections.push(field.column);
    }
    result.facts.push(fact);
  }
  if (typeConfirmation) result.confirmations.unshift(typeConfirmation);

  validateEntities(output.entity_ops ?? [], context, merged, result);

  for (const column of pendingColumns) {
    if (column in result.patch) continue;
    const field = fieldOf(column);
    if (!field) continue;
    if (result.pending.some((p) => p.field === column)) continue;
    result.pending.push({ field: column, label_fr: `${field.label} ?` });
  }

  for (const code of output.out_of_step ?? []) {
    const owner = stepOfColumn(code);
    if (!owner || owner.step === step) continue;
    if (result.out_of_step.some((o) => o.field === code)) continue;
    result.out_of_step.push({
      field: code,
      step: owner.step,
      label_fr: `${owner.field.label} → ${STEP_LABELS[owner.step]}`,
    });
  }

  if (schema.lifestyle) validateLifestyleItems(output, context, result);

  result.confirmations.forEach((confirmation, index) => {
    confirmation.id = `c${index + 1}`;
  });
  return withTypography(result);
}

/** Every French label of [turn] with its no-break spaces. */
function withTypography(turn: ValidatedTurn): ValidatedTurn {
  const change = (op: EntityChange) => {
    op.label_fr = typo(op.label_fr);
    if (op.changed_fr) op.changed_fr = typo(op.changed_fr);
  };
  for (const fact of turn.facts) {
    fact.label_fr = typo(fact.label_fr);
    if (fact.changed_fr) fact.changed_fr = typo(fact.changed_fr);
  }
  for (const pill of turn.pending) pill.label_fr = typo(pill.label_fr);
  turn.entity_ops.forEach(change);
  for (const confirmation of turn.confirmations) {
    confirmation.label_fr = typo(confirmation.label_fr);
    confirmation.entity_ops.forEach(change);
  }
  for (const item of turn.out_of_step) item.label_fr = typo(item.label_fr);
  return turn;
}

function validateLifestyleItems(
  output: ModelOutput,
  context: ValidationContext,
  result: ValidatedTurn,
): void {
  const known = {
    asset: (context.lifestyleLabels?.asset ?? []).map(normalize),
    watch_point: (context.lifestyleLabels?.watch_point ?? []).map(normalize),
  };
  for (const item of output.lifestyle_items) {
    const kind = item.kind;
    const label = item.label.trim().replace(/\s+/g, " ");
    const rejectItem = (reason: RejectionReason) =>
      result.rejected.push({ field: `lifestyle:${kind}`, value: label, reason });
    if (kind !== "asset" && kind !== "watch_point") {
      rejectItem("invalid_value");
      continue;
    }
    const length = [...label].length;
    if (length < LIFESTYLE_ITEM_MIN || length > LIFESTYLE_ITEM_MAX) {
      rejectItem("out_of_range");
      continue;
    }
    if (!quoteFound(item.quote, context.transcript)) {
      rejectItem("quote_not_found");
      continue;
    }
    const key = normalize(label);
    if (known.asset.includes(key) || known.watch_point.includes(key)) {
      rejectItem("duplicate");
      continue;
    }
    if (known[kind].length >= LIFESTYLE_ITEMS_PER_KIND) {
      rejectItem("full");
      continue;
    }
    known[kind].push(key);
    result.lifestyle_items.push({ kind, label });
  }
}

// ---------------------------------------------------------------------------
// Entities: rooms (V5c), previous estimates (V3), co-owners (V1).
// ---------------------------------------------------------------------------

const GLAZING_WORDS = ["vitr", "fenetre", "baie", "carreau", "menuiserie", "ouverture"];

function roomLabel(values: Record<string, unknown>): string {
  return [
    values.name as string,
    values.level ? ROOM_LEVELS[values.level as keyof typeof ROOM_LEVELS] : null,
    typeof values.area_m2 === "number" ? `${formatNumber(values.area_m2)} m²` : null,
    values.floor_covering
      ? FLOOR_COVERINGS[values.floor_covering as keyof typeof FLOOR_COVERINGS]
      : null,
    values.glazing ? GLAZINGS[values.glazing as keyof typeof GLAZINGS] : null,
  ].filter((part) => part).join(" · ");
}

function estimateLabel(values: Record<string, unknown>): string {
  return [
    typeof values.price_eur === "number" ? `Estimation ${formatNumber(values.price_eur)} €` : null,
    typeof values.estimated_month === "string"
      ? values.estimated_month.slice(5, 7) + "/" + values.estimated_month.slice(0, 4)
      : null,
    values.agency_name as string | undefined,
  ].filter((part) => part).join(" · ");
}

/** Validates the fields of one entity operation: the accepted values,
 * whether one has a medium confidence, and the fields asked again. */
function entityFields(
  entity: EntityDef,
  op: ModelEntityOp,
  context: ValidationContext,
  result: ValidatedTurn,
  parseContext: { year: number; month: number; values: Record<string, unknown> },
): { values: Record<string, unknown>; medium: boolean; failed: string[]; dims?: [number, number] } {
  const values: Record<string, unknown> = {};
  const failed: string[] = [];
  let medium = false;
  let dims: [number, number] | undefined;
  const interactive = context.interactive === true;
  for (const said of op.fields) {
    const field = entity.fields.find((f) => f.column === said.field);
    const key = `${entity.name}:${said.field}`;
    if (!field) {
      result.rejected.push({ field: key, value: said.value, reason: "unknown_field" });
      continue;
    }
    if (field.column in values) continue;
    if (!quoteFound(said.quote, context.transcript)) {
      result.rejected.push({ field: key, value: said.value, reason: "quote_not_found" });
      failed.push(field.column);
      continue;
    }
    const isMedium = said.confidence >= VOICE_DEFAULTS.confirmFrom &&
      said.confidence < MIN_CONFIDENCE;
    if (!(said.confidence >= MIN_CONFIDENCE) && !(isMedium && interactive)) {
      result.rejected.push({ field: key, value: said.value, reason: "low_confidence" });
      failed.push(field.column);
      continue;
    }
    const parsed = parseValue(field, said.value, parseContext);
    if (!parsed.ok) {
      result.rejected.push({ field: key, value: said.value, reason: parsed.reason });
      failed.push(field.column);
      continue;
    }
    let weak = anchored(field, parsed, said.quote, context.transcript);
    if (
      !weak && field.column === "glazing" &&
      !GLAZING_WORDS.some((w) => normalize(said.quote).includes(w))
    ) {
      weak = "anchor_missing";
    }
    if (!weak && entity.name === "co_owner" && !isPersonName(parsed.value as string)) {
      weak = "invalid_value";
    }
    if (!weak && entity.name === "room" && field.column === "name") {
      const kind = roomKindOf(parsed.value as string);
      if (!kind && !textCovered(parsed.value as string, context.transcript)) weak = "not_covered";
    }
    if (weak) {
      result.rejected.push({ field: key, value: said.value, reason: weak });
      failed.push(field.column);
      continue;
    }
    if (parsed.dimensions) dims = parsed.dimensions;
    medium ||= isMedium;
    values[field.column] = parsed.value;
  }
  return { values, medium, failed, dims };
}

function validateEntities(
  ops: ModelEntityOp[],
  context: ValidationContext,
  merged: Record<string, unknown>,
  result: ValidatedTurn,
): void {
  const schema = stepSchema(context.step);
  const interactive = context.interactive === true;
  const parseContext = {
    year: context.currentYear,
    month: context.currentMonth ?? 12,
    values: merged,
  };
  const rooms = [...(context.rooms ?? [])];
  const estimates = context.estimates ?? [];
  let coOwners = context.coOwnersCount ?? 0;
  let deletes = 0;
  let estimatesCount = estimates.length;
  const pending = (label: string) => {
    if (!result.pending.some((p) => p.label_fr === label)) {
      result.pending.push({ field: "entity", label_fr: label });
    }
  };
  const habitable = () => rooms.filter((r) => !r.is_annex).reduce((sum, r) => sum + r.area_m2, 0);

  ops.slice(MAX_ENTITY_OPS).forEach((op) =>
    result.rejected.push({ field: op.entity, value: op.op, reason: "full" })
  );
  for (const op of ops.slice(0, MAX_ENTITY_OPS)) {
    const entity = schema.entities.find((e) => e.name === op.entity);
    const opName = op.op as "create" | "update" | "delete";
    if (!entity) {
      result.rejected.push({ field: op.entity, value: op.op, reason: "unknown_field" });
      continue;
    }
    if (!entity.ops.includes(opName)) {
      result.rejected.push({ field: op.entity, value: op.op, reason: "not_allowed" });
      continue;
    }
    const { values, medium, failed, dims } = entityFields(
      entity,
      op,
      context,
      result,
      parseContext,
    );
    const corrected = op.correction === true;
    const change = (
      target: string,
      opValue: "create" | "update" | "delete",
      vals: Record<string, unknown>,
      label: string,
      changed?: string,
    ): EntityChange => ({
      entity: entity.name,
      op: opValue,
      target,
      values: vals,
      label_fr: corrected ? `${label} (corrigé)` : label,
      ...(changed ? { changed_fr: changed } : {}),
      ...(corrected ? { corrected: true } : {}),
    });
    const apply = (item: EntityChange, reason: ConfirmationReason | null, label?: string) => {
      if (reason && interactive) {
        result.confirmations.push({
          id: "",
          reason,
          label_fr: label ?? `${item.label_fr} ?`,
          patch: entity.name === "co_owner" ? { ownership_type: "multiple" } : {},
          entity_ops: [item],
        });
        return;
      }
      if (reason && reason !== "medium_confidence" && reason !== "strong_change") {
        result.rejected.push({ field: entity.name, value: op.op, reason: "not_allowed" });
        return;
      }
      if (reason) {
        pending(`${item.label_fr} ?`);
        return;
      }
      result.entity_ops.push(item);
      if (corrected) result.corrections.push(`${entity.name}:${item.target}`);
    };

    if (entity.name === "room") {
      if (opName === "delete") {
        const found = designate(op.target, op.target_quote, rooms, context.lastRoomRef ?? null);
        if (!found.ok) {
          result.rejected.push({ field: "room", value: op.target, reason: found.reason });
          if (found.reason === "ambiguous") {
            pending(`Quelle pièce : ${found.candidates.map((r) => r.name).join(", ")} ?`);
          }
          continue;
        }
        if (++deletes > 1) {
          result.rejected.push({ field: "room", value: op.target, reason: "full" });
          continue;
        }
        apply(
          change(found.room.ref, "delete", {}, `Supprimer ${found.room.name}`),
          "delete",
          `Supprimer ${found.room.name} (${formatNumber(found.room.area_m2)} m²) ?`,
        );
        continue;
      }
      // Copy from another room ("même sol que le séjour").
      if (op.copy_from && op.copy_from !== "new" && op.copy_from !== "" && op.copy_fields?.length) {
        const source = rooms.find((r) => r.ref === op.copy_from);
        const quote = op.copy_quote ?? "";
        const said = /\b(meme|pareil|idem|comme|identique)\b/.test(normalize(quote)) &&
          quoteFound(quote, context.transcript);
        if (source && said) {
          for (const column of op.copy_fields) {
            const copied = source[column as keyof RoomRow];
            if (!(column in values) && copied !== null && copied !== undefined) {
              values[column] = copied;
            }
          }
        } else {
          result.rejected.push({
            field: "room:copy_from",
            value: op.copy_from,
            reason: "anchor_missing",
          });
        }
      }
      let target = op.target;
      let opValue: "create" | "update" = opName;
      let mergeWith: RoomRow | null = null;
      if (opName === "update") {
        const found = designate(op.target, op.target_quote, rooms, context.lastRoomRef ?? null);
        if (!found.ok) {
          result.rejected.push({ field: "room", value: op.target, reason: found.reason });
          if (found.reason === "ambiguous") {
            pending(`Quelle pièce : ${found.candidates.map((r) => r.name).join(", ")} ?`);
          }
          continue;
        }
        target = found.room.ref;
        delete values.name;
      } else {
        target = "new";
        const name = values.name as string | undefined;
        if (name === undefined || values.area_m2 === undefined) {
          pending(name ? `${upperFirst(name)} : surface ?` : "Pièce ?");
          continue;
        }
        const kind = roomKindOf(name);
        const nameQuote = op.fields.find((f) => f.field === "name")?.quote ?? "";
        const duplicates = duplicateOf(kind, nameQuote, rooms);
        if (duplicates.length > 1) {
          result.rejected.push({ field: "room", value: name, reason: "ambiguous" });
          pending(`Quelle pièce : ${duplicates.map((r) => r.name).join(", ")} ?`);
          continue;
        }
        if (duplicates.length === 1) {
          mergeWith = duplicates[0];
          opValue = "update";
          target = mergeWith.ref;
          delete values.name;
        } else {
          values.name = kind ? kind.label : upperFirst(name);
          values.kind = kind?.kind ?? "other";
        }
      }
      if (failed.length && Object.keys(values).length === 0) {
        pending(`${(rooms.find((r) => r.ref === target)?.name) ?? "Pièce"} ?`);
        continue;
      }
      if (rooms.length >= entity.max && opValue === "create") {
        result.rejected.push({ field: "room", value: String(values.name), reason: "full" });
        continue;
      }
      const existing = rooms.find((r) => r.ref === target);
      const after: RoomRow = existing ? { ...existing, ...values } as RoomRow : {
        ref: `new${result.entity_ops.length}`,
        name: values.name as string,
        level: (values.level as string) ?? null,
        area_m2: values.area_m2 as number,
        floor_covering: (values.floor_covering as string) ?? null,
        glazing: (values.glazing as string) ?? null,
        ceiling_height_m: (values.ceiling_height_m as number) ?? null,
        is_annex: roomKindOf(values.name as string)?.annex ?? false,
      };
      const before = habitable();
      const others = rooms.filter((r) => r.ref !== target);
      const total = others.filter((r) => !r.is_annex).reduce((s, r) => s + r.area_m2, 0) +
        (after.is_annex ? 0 : after.area_m2);
      if (total > MAX_LIVING_AREA && total > before) {
        result.rejected.push({
          field: "room:area_m2",
          value: String(after.area_m2),
          reason: "inconsistent",
        });
        pending(`${after.name} : surface ?`);
        continue;
      }
      const label = roomLabel(opValue === "create" ? values : { ...after });
      let changed: string | undefined;
      let strong = false;
      if (
        existing && typeof values.area_m2 === "number" &&
        Math.abs(values.area_m2 - existing.area_m2) >= 0.005
      ) {
        changed = `Modifiée : ${formatNumber(existing.area_m2)} → ${
          formatNumber(values.area_m2)
        } m²`;
        strong = isStrongChange(ROOM_AREA_FIELD, existing.area_m2, values.area_m2);
      }
      const item = change(target, opValue, values, label, changed);
      if (dims) {
        item.values.dimensions = typo(`${formatNumber(dims[0])} × ${formatNumber(dims[1])} m`);
      }
      const reason: ConfirmationReason | null = mergeWith
        ? "merge_room"
        : medium
        ? "medium_confidence"
        : strong
        ? "strong_change"
        : null;
      const confirmLabel = mergeWith
        ? `Modifier ${mergeWith.name}${changed ? ` : ${changed.slice(11)}` : ""} ?`
        : undefined;
      if (mergeWith && !interactive) {
        result.rejected.push({ field: "room", value: mergeWith.name, reason: "ambiguous" });
        pending(`${mergeWith.name} ?`);
        continue;
      }
      apply(item, reason, confirmLabel);
      if (!reason) {
        if (existing) Object.assign(existing, after);
        else rooms.push(after);
      }
      continue;
    }

    if (entity.name === "previous_estimate") {
      if (opName === "create") {
        if (values.price_eur === undefined) {
          pending("Estimation : montant ?");
          continue;
        }
        if (estimatesCount >= entity.max) {
          result.rejected.push({ field: "previous_estimate", value: op.op, reason: "full" });
          continue;
        }
        estimatesCount++;
        apply(
          change("new", "create", values, estimateLabel(values)),
          medium ? "medium_confidence" : null,
        );
        if (!medium && merged.previously_estimated !== true) {
          merged.previously_estimated = true;
          result.patch.previously_estimated = true;
          result.facts.push({ field: "previously_estimated", label_fr: "Déjà estimé : oui" });
        }
        continue;
      }
      const target = estimates.find((e) => e.ref === op.target);
      if (!target) {
        result.rejected.push({
          field: "previous_estimate",
          value: op.target,
          reason: "unknown_target",
        });
        continue;
      }
      if (opName === "delete") {
        apply(
          change(target.ref, "delete", {}, `Supprimer ${estimateLabel({ ...target })}`),
          "delete",
          `Supprimer l’estimation de ${formatNumber(target.price_eur ?? 0)} € ?`,
        );
        continue;
      }
      if (Object.keys(values).length === 0) {
        pending("Estimation ?");
        continue;
      }
      apply(
        change(target.ref, "update", values, estimateLabel({ ...target, ...values })),
        medium ? "medium_confidence" : null,
      );
      continue;
    }

    // co_owner: created only, always confirmed (names in STT).
    if (merged.ownership_type === "single") {
      result.rejected.push({ field: "co_owner", value: op.op, reason: "inconsistent" });
      continue;
    }
    if (values.first_name === undefined || values.last_name === undefined) {
      pending("Co-propriétaire : prénom et nom ?");
      continue;
    }
    if (coOwners >= entity.max) {
      result.rejected.push({ field: "co_owner", value: op.op, reason: "full" });
      continue;
    }
    coOwners++;
    const name = `${values.first_name} ${values.last_name}`;
    apply(change("new", "create", values, name), "co_owner", `${name} ?`);
  }
}

const ROOM_AREA_FIELD: FieldDef = {
  column: "area_m2",
  label: "Surface",
  kind: { type: "area", min: 0.5, max: 500 },
};

/** Parses the model's JSON answer, or throws. */
export function parseModelOutput(content: string): ModelOutput {
  const start = content.indexOf("{");
  const end = content.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error("No JSON object");
  // deno-lint-ignore no-explicit-any
  const json: any = JSON.parse(content.slice(start, end + 1));
  const list = (value: unknown): unknown[] => Array.isArray(value) ? value : [];
  const text = (value: unknown): string => typeof value === "string" ? value : "";
  const answers = list(json.answers)
    // deno-lint-ignore no-explicit-any
    .filter((a: any) => a && typeof a.field === "string")
    // deno-lint-ignore no-explicit-any
    .map((a: any): ModelAnswer => ({
      field: a.field,
      value: String(a.value ?? ""),
      confidence: typeof a.confidence === "number" ? a.confidence : 0,
      quote: text(a.quote),
      ...(a.correction === true ? { correction: true } : {}),
    }));
  const entityOps = list(json.entity_ops)
    // deno-lint-ignore no-explicit-any
    .filter((o: any) => o && typeof o.entity === "string" && typeof o.op === "string")
    // deno-lint-ignore no-explicit-any
    .map((o: any): ModelEntityOp => ({
      entity: o.entity,
      op: o.op,
      target: text(o.target) || "new",
      target_quote: text(o.target_quote),
      ...(o.correction === true ? { correction: true } : {}),
      fields: list(o.fields)
        // deno-lint-ignore no-explicit-any
        .filter((f: any) => f && typeof f.field === "string")
        // deno-lint-ignore no-explicit-any
        .map((f: any) => ({
          field: f.field,
          value: String(f.value ?? ""),
          confidence: typeof f.confidence === "number" ? f.confidence : 0,
          quote: text(f.quote),
        })),
      ...(typeof o.copy_from === "string" && o.copy_from ? { copy_from: o.copy_from } : {}),
      ...(Array.isArray(o.copy_fields) && o.copy_fields.length
        ? { copy_fields: o.copy_fields.filter((c: unknown) => typeof c === "string") }
        : {}),
      ...(typeof o.copy_quote === "string" && o.copy_quote ? { copy_quote: o.copy_quote } : {}),
    }));
  const output: ModelOutput = {
    reply_fr: text(json.reply_fr).trim(),
    answers,
    lifestyle_items: list(json.lifestyle_items)
      // deno-lint-ignore no-explicit-any
      .filter((i: any) => i && typeof i.label === "string")
      // deno-lint-ignore no-explicit-any
      .map((i: any) => ({ kind: String(i.kind), label: i.label, quote: text(i.quote) })),
    next_field: typeof json.next_field === "string" ? json.next_field : "none",
    done: json.done === true,
  };
  if (entityOps.length) output.entity_ops = entityOps;
  const outOfStep = list(json.out_of_step).filter((c): c is string => typeof c === "string");
  if (outOfStep.length) output.out_of_step = outOfStep;
  return output;
}
