// Server-side validation of the agent's answers: whitelisted fields and
// codes, screen rules (bounds, consistency), literal quotes, confidence.
// Nothing the model says reaches the dossier without passing here, and the
// app then writes it itself (RLS, lock).

import {
  type AgentStep,
  fieldByColumn,
  type FieldDef,
  isAsked,
  LIFESTYLE_ITEM_MAX,
  LIFESTYLE_ITEM_MIN,
  LIFESTYLE_ITEMS_PER_KIND,
  type PropertyValues,
} from "./schema.ts";

export const MIN_CONFIDENCE = 0.7;

export interface ModelAnswer {
  field: string;
  value: string;
  confidence: number;
  quote: string;
}

export interface ModelLifestyleItem {
  kind: string;
  label: string;
  quote: string;
}

export interface ModelOutput {
  reply_fr: string;
  answers: ModelAnswer[];
  lifestyle_items: ModelLifestyleItem[];
  next_field: string;
  done: boolean;
}

export interface Pill {
  field: string;
  label_fr: string;
}

export interface Rejection {
  field: string;
  value: string;
  reason:
    | "unknown_field"
    | "not_asked"
    | "invalid_value"
    | "out_of_range"
    | "inconsistent"
    | "quote_not_found"
    | "low_confidence"
    | "duplicate"
    | "full";
}

export interface ValidatedTurn {
  patch: Record<string, unknown>;
  facts: Pill[];
  pending: Pill[];
  lifestyle_items: { kind: "asset" | "watch_point"; label: string }[];
  suggestions: Record<string, string>;
  rejected: Rejection[];
}

export interface ValidationContext {
  step: AgentStep;
  /** Current `properties` values (with `property_type`). */
  values: PropertyValues;
  transcript: string;
  currentYear: number;
  /** Labels already listed on V6 (saved or drafted), per kind. */
  lifestyleLabels?: { asset: string[]; watch_point: string[] };
}

/** Lower case, no accents nor punctuation, single spaces. */
export function normalize(text: string): string {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Whether [quote] is a literal (normalized) extract of [transcript]. */
export function quoteFound(quote: string, transcript: string): boolean {
  const q = normalize(quote);
  return q.length > 0 && ` ${normalize(transcript)} `.includes(` ${q} `);
}

function parseNumber(raw: string): number | null {
  const compact = raw.replace(/\s| | /g, "").replace(",", ".")
    .replace(/m²|m2|m$/i, "");
  return /^\d+(\.\d+)?$/.test(compact) ? Number(compact) : null;
}

function frenchNumber(value: number): string {
  return String(Math.round(value * 100) / 100).replace(".", ",");
}

function lowerFirst(text: string): string {
  return text.charAt(0).toLowerCase() + text.slice(1);
}

type Parsed = { ok: true; value: unknown } | {
  ok: false;
  reason: Rejection["reason"];
};

function parseValue(field: FieldDef, raw: string, year: number): Parsed {
  const kind = field.kind;
  const text = raw.trim();
  switch (kind.type) {
    case "year": {
      if (!/^\d{4}$/.test(text)) return { ok: false, reason: "invalid_value" };
      const value = Number(text);
      return value < kind.min || value > year
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
    case "int": {
      if (!/^\d+$/.test(text)) return { ok: false, reason: "invalid_value" };
      const value = Number(text);
      return value < kind.min || value > kind.max
        ? { ok: false, reason: "out_of_range" }
        : { ok: true, value };
    }
    case "enum":
      return text in kind.codes
        ? { ok: true, value: text }
        : { ok: false, reason: "invalid_value" };
    case "list": {
      const codes = text.split(/[,;]/).map((code) => code.trim()).filter((
        code,
      ) => code.length > 0);
      if (codes.length === 0 || codes.some((code) => !(code in kind.codes))) {
        return { ok: false, reason: "invalid_value" };
      }
      return { ok: true, value: codes };
    }
    case "text": {
      const value = text.slice(0, kind.max);
      return value.length === 0 ? { ok: false, reason: "invalid_value" } : { ok: true, value };
    }
  }
}

/** The French pill of an accepted answer ("Construction 1998"). */
export function factLabel(field: FieldDef, value: unknown): string {
  const kind = field.kind;
  switch (kind.type) {
    case "year":
      return `${field.label} ${value}`;
    case "decimal":
      return field.column.startsWith("pool_")
        ? `${field.label} ${frenchNumber(value as number)} m`
        : `${field.label} ${frenchNumber(value as number)} m²`;
    case "int":
      return field.column === "noise_level"
        ? `${field.label} ${value}/10`
        : `${value} ${lowerFirst(field.label)}`;
    case "enum": {
      const label = kind.codes[value as string];
      return field.column === "wall_material" ? label : `${field.label} ${lowerFirst(label)}`;
    }
    case "list":
      return (value as string[]).map((code) => kind.codes[code]).join(", ");
    case "text":
      return field.label;
  }
}

/** Validates a model answer for [context]: see [ValidatedTurn]. */
export function validateTurn(
  output: ModelOutput,
  context: ValidationContext,
): ValidatedTurn {
  const { step, values, transcript, currentYear } = context;
  const result: ValidatedTurn = {
    patch: {},
    facts: [],
    pending: [],
    lifestyle_items: [],
    suggestions: {},
    rejected: [],
  };
  const merged: PropertyValues = { ...values };
  const accepted: { field: FieldDef; value: unknown }[] = [];
  const pendingColumns = new Set<string>();

  const reject = (answer: ModelAnswer, reason: Rejection["reason"]) => {
    result.rejected.push({ field: answer.field, value: answer.value, reason });
  };

  // Lists first: they decide whether the heat pump / pool fields are asked.
  const answers = [...output.answers].sort((a, b) => {
    const rank = (answer: ModelAnswer) =>
      fieldByColumn(step, answer.field)?.kind.type === "list" ? 0 : 1;
    return rank(a) - rank(b);
  });

  for (const answer of answers) {
    const field = fieldByColumn(step, answer.field);
    if (!field) {
      reject(answer, "unknown_field");
      continue;
    }
    if (!quoteFound(answer.quote, transcript)) {
      reject(answer, "quote_not_found");
      continue;
    }
    if (!isAsked(field, merged)) {
      reject(answer, "not_asked");
      continue;
    }
    if (!(answer.confidence >= MIN_CONFIDENCE)) {
      reject(answer, "low_confidence");
      pendingColumns.add(field.column);
      continue;
    }
    const parsed = parseValue(field, answer.value, currentYear);
    if (!parsed.ok) {
      reject(answer, parsed.reason);
      pendingColumns.add(field.column);
      continue;
    }
    let value = parsed.value;
    if (field.kind.type === "list") {
      const existing = Array.isArray(merged[field.column]) ? merged[field.column] as string[] : [];
      const union = new Set([...existing, ...(value as string[])]);
      value = Object.keys(field.kind.codes).filter((code) => union.has(code));
    }
    merged[field.column] = value;
    accepted.push({ field, value });
  }

  // Cross-field rules, on the dossier as it would be after this turn.
  const consistent = (field: FieldDef, value: unknown): boolean => {
    const num = (column: string) =>
      typeof merged[column] === "number" ? merged[column] as number : null;
    const value_ = value as number;
    switch (field.column) {
      case "roof_year": {
        const built = num("construction_year");
        return built === null || value_ >= built;
      }
      case "construction_year": {
        const roof = num("roof_year");
        return roof === null || roof >= value_;
      }
      case "living_room_area_m2": {
        const living = num("living_area_m2");
        return living === null || value_ <= living;
      }
      case "living_area_m2": {
        const room = num("living_room_area_m2");
        return room === null || room <= value_;
      }
      case "bedrooms_count": {
        const rooms = num("rooms_count");
        return rooms === null || value_ <= rooms;
      }
      case "rooms_count": {
        const bedrooms = num("bedrooms_count");
        return bedrooms === null || bedrooms <= value_;
      }
      default:
        return true;
    }
  };

  for (const { field, value } of accepted) {
    if (!consistent(field, value)) {
      result.rejected.push({
        field: field.column,
        value: String(value),
        reason: "inconsistent",
      });
      pendingColumns.add(field.column);
      continue;
    }
    if (field.kind.type === "text") {
      result.suggestions[field.column] = value as string;
      continue;
    }
    result.patch[field.column] = value;
    result.facts.push({
      field: field.column,
      label_fr: factLabel(field, value),
    });
  }

  for (const column of pendingColumns) {
    if (column in result.patch) continue;
    const field = fieldByColumn(step, column)!;
    result.pending.push({ field: column, label_fr: `${field.label} ?` });
  }

  if (step === "lifestyle") {
    const known = {
      asset: (context.lifestyleLabels?.asset ?? []).map(normalize),
      watch_point: (context.lifestyleLabels?.watch_point ?? []).map(normalize),
    };
    for (const item of output.lifestyle_items) {
      const kind = item.kind;
      const label = item.label.trim().replace(/\s+/g, " ");
      const rejectItem = (reason: Rejection["reason"]) =>
        result.rejected.push({
          field: `lifestyle:${kind}`,
          value: label,
          reason,
        });
      if (kind !== "asset" && kind !== "watch_point") {
        rejectItem("invalid_value");
        continue;
      }
      const length = [...label].length;
      if (length < LIFESTYLE_ITEM_MIN || length > LIFESTYLE_ITEM_MAX) {
        rejectItem("out_of_range");
        continue;
      }
      if (!quoteFound(item.quote, transcript)) {
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
  return result;
}

/** Parses the model's JSON answer, or throws. */
export function parseModelOutput(content: string): ModelOutput {
  const start = content.indexOf("{");
  const end = content.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error("No JSON object");
  // deno-lint-ignore no-explicit-any
  const json: any = JSON.parse(content.slice(start, end + 1));
  const answers = Array.isArray(json.answers) ? json.answers : [];
  const items = Array.isArray(json.lifestyle_items) ? json.lifestyle_items : [];
  return {
    reply_fr: typeof json.reply_fr === "string" ? json.reply_fr.trim() : "",
    answers: answers
      // deno-lint-ignore no-explicit-any
      .filter((a: any) => a && typeof a.field === "string")
      // deno-lint-ignore no-explicit-any
      .map((a: any) => ({
        field: a.field,
        value: String(a.value ?? ""),
        confidence: typeof a.confidence === "number" ? a.confidence : 0,
        quote: typeof a.quote === "string" ? a.quote : "",
      })),
    lifestyle_items: items
      // deno-lint-ignore no-explicit-any
      .filter((i: any) => i && typeof i.label === "string")
      // deno-lint-ignore no-explicit-any
      .map((i: any) => ({
        kind: String(i.kind),
        label: i.label,
        quote: typeof i.quote === "string" ? i.quote : "",
      })),
    next_field: typeof json.next_field === "string" ? json.next_field : "none",
    done: json.done === true,
  };
}
