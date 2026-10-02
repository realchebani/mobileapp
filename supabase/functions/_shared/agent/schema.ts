// Fields the voice agent may fill, per tunnel step, and the JSON Schema of
// its answer. The fields themselves live in the step registry (./steps/):
// the same `properties` columns, codes and rules as the screens.

import { VOICE_DEFAULTS } from "./defaults.ts";
import {
  AGENT_STEPS,
  type AgentStep,
  crossStepTargets,
  type EntityDef,
  entityOf,
  type FieldDef,
  fieldOf,
  isAsked,
  stepSchema,
  VOICE_AUDIT_TYPES,
} from "./steps/index.ts";

export {
  AGENT_STEPS,
  type AgentStep,
  codesOf,
  type CrossStepTargets,
  crossStepTargets,
  type EntityDef,
  type FieldDef,
  type FieldKind,
  isAsked,
  isStep,
  type PropertyType,
  stepSchema,
  voiceStepsFor,
} from "./steps/index.ts";
export { TECHNICAL_FIELDS } from "./steps/technical.ts";
export {
  LIFESTYLE_FIELDS,
  LIFESTYLE_ITEM_MAX,
  LIFESTYLE_ITEM_MIN,
  LIFESTYLE_ITEMS_PER_KIND,
} from "./steps/lifestyle.ts";

/** Property types of the V4 "Night" audit (the app's
 * `PropertyTypeProfile.voiceAudit`). */
export const VOICE_TYPES = VOICE_AUDIT_TYPES;

/** Whether the V4 "Night" audit serves [type] (null: not chosen yet). */
export function isVoiceType(type: string | null): boolean {
  return type === null || (VOICE_TYPES as readonly string[]).includes(type);
}

export type PropertyValues = Record<string, unknown>;

export function stepFields(step: AgentStep): FieldDef[] {
  return stepSchema(step).fields;
}

function isEmpty(value: unknown): boolean {
  return value === null || value === undefined ||
    (Array.isArray(value) && value.length === 0) ||
    (typeof value === "string" && value.trim() === "");
}

/** The asked fields of [step] still without an answer, in question order. */
export function missingFields(step: AgentStep, values: PropertyValues): FieldDef[] {
  return stepFields(step).filter((field) =>
    isAsked(field, values) && isEmpty(values[field.column])
  );
}

/** The fields of [step] that can be asked for this property type,
 * including the conditional ones (heat pump, pool) not asked yet: the
 * seller may give them in the same sentence as their condition. */
export function promptFields(step: AgentStep, values: PropertyValues): FieldDef[] {
  const assumed = {
    ...values,
    heating_systems: ["pac"],
    outdoor_equipment: ["piscine"],
  };
  return stepFields(step).filter((field) => isAsked(field, assumed));
}

/** The condition of a conditional field, in French (prompt). */
export function conditionOf(field: FieldDef): string | null {
  switch (field.condition) {
    case "heat_pump":
      return "seulement s’il y a une pompe à chaleur";
    case "pool":
      return "seulement s’il y a une piscine";
    default:
      return null;
  }
}

export function fieldByColumn(step: AgentStep, column: string): FieldDef | undefined {
  return fieldOf(step, column);
}

export function entityByName(step: AgentStep, name: string): EntityDef | undefined {
  return entityOf(step, name);
}

/** The `properties` columns of the other steps (answers given out of
 * step are reported, never written). */
export function otherStepColumns(step: AgentStep): string[] {
  return AGENT_STEPS.filter((other) => other !== step)
    .flatMap((other) => stepFields(other).map((field) => field.column));
}

function answerSchema(columns: string[]): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: ["field", "value", "confidence", "quote", "correction"],
    properties: {
      field: { type: "string", enum: columns },
      value: { type: "string" },
      confidence: { type: "number" },
      quote: { type: "string" },
      correction: { type: "boolean" },
    },
  };
}

function entityOpSchema(step: AgentStep, entities: EntityDef[]): Record<string, unknown> {
  const fieldColumns = [...new Set(entities.flatMap((e) => e.fields.map((f) => f.column)))];
  const properties: Record<string, unknown> = {
    entity: { type: "string", enum: entities.map((e) => e.name) },
    op: { type: "string", enum: ["create", "update", "delete"] },
    target: { type: "string" },
    target_quote: { type: "string" },
    correction: { type: "boolean" },
    fields: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["field", "value", "confidence", "quote"],
        properties: {
          field: { type: "string", enum: fieldColumns },
          value: { type: "string" },
          confidence: { type: "number" },
          quote: { type: "string" },
        },
      },
    },
  };
  if (step === "rooms") {
    properties.copy_from = { type: "string" };
    properties.copy_fields = {
      type: "array",
      items: { type: "string", enum: ["level", "floor_covering", "glazing", "ceiling_height_m"] },
    };
    properties.copy_quote = { type: "string" };
  }
  return {
    type: "object",
    additionalProperties: false,
    required: Object.keys(properties),
    properties,
  };
}

const said = {
  type: "object",
  additionalProperties: false,
  required: ["field", "value", "confidence", "quote"],
  properties: {
    field: { type: "string" },
    value: { type: "string" },
    confidence: { type: "number" },
    quote: { type: "string" },
  },
};

function strict(properties: Record<string, unknown>): Record<string, unknown> {
  return {
    type: "object",
    additionalProperties: false,
    required: Object.keys(properties),
    properties,
  };
}

const lifestyleItemSchema = strict({
  kind: { type: "string", enum: ["asset", "watch_point"] },
  label: { type: "string" },
  quote: { type: "string" },
});

/** The `cross_step` part of the answer (plan §7): values said for another
 * step, validated with that step's definitions, then kept as pending
 * answers. Its enums depend on the step and the property type. */
export function crossStepSchema(
  step: AgentStep,
  values: PropertyValues,
): Record<string, unknown> {
  const targets = crossStepTargets(step, values);
  const columns = targets.fields.map((t) => t.field.column);
  const entityFields = [
    ...new Set(targets.entities.flatMap((t) => t.entity.fields.map((f) => f.column))),
  ];
  return strict({
    answers: {
      type: "array",
      items: strict({
        field: { type: "string", enum: columns.length ? columns : ["none"] },
        value: { type: "string" },
        confidence: { type: "number" },
        quote: { type: "string" },
      }),
    },
    entities: {
      type: "array",
      items: strict({
        entity: {
          type: "string",
          enum: targets.entities.length ? targets.entities.map((t) => t.entity.name) : ["none"],
        },
        fields: {
          type: "array",
          items: {
            ...said,
            properties: {
              ...said.properties,
              field: { type: "string", enum: entityFields.length ? entityFields : ["none"] },
            },
          },
        },
      }),
    },
    lifestyle_items: { type: "array", items: lifestyleItemSchema },
    notes: {
      type: "array",
      items: strict({
        step: {
          type: "string",
          enum: targets.noteSteps.length ? targets.noteSteps : ["none"],
        },
        text: { type: "string" },
        quote: { type: "string" },
      }),
    },
  });
}

/** The JSON Schema (strict structured output) of an agent answer. [values]
 * (the dossier and the draft) decide the other steps' fields of
 * `cross_step` (property type). */
export function outputSchema(
  step: AgentStep,
  values: PropertyValues = {},
): Record<string, unknown> {
  const schema = stepSchema(step);
  const columns = schema.fields.map((field) => field.column);
  const properties: Record<string, unknown> = {
    reply_fr: { type: "string" },
    answers: { type: "array", items: answerSchema(columns.length ? columns : ["none"]) },
  };
  if (schema.entities.length) {
    properties.entity_ops = { type: "array", items: entityOpSchema(step, schema.entities) };
  }
  if (schema.lifestyle) {
    properties.lifestyle_items = { type: "array", items: lifestyleItemSchema };
  }
  if (VOICE_DEFAULTS.stepNotes) {
    properties.notes = {
      type: "array",
      items: strict({ text: { type: "string" }, quote: { type: "string" } }),
    };
  }
  if (VOICE_DEFAULTS.crossStepPrefill) {
    properties.cross_step = crossStepSchema(step, values);
  }
  properties.out_of_step = {
    type: "array",
    items: { type: "string", enum: otherStepColumns(step) },
  };
  properties.next_field = {
    type: "string",
    enum: [...columns, ...schema.entities.map((e) => e.name), "none"],
  };
  properties.done = { type: "boolean" };
  return {
    type: "object",
    additionalProperties: false,
    required: Object.keys(properties),
    properties,
  };
}
