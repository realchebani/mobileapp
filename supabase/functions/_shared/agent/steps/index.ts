// The step registry of the voice agent: one StepSchema per tunnel step
// (plan §4.4), and the rules shared by validation and prompt (which field
// is asked for which property, which step is voiced for which type).

import { VOICE_DEFAULTS } from "../defaults.ts";
import { CONTEXT_STEP } from "./context.ts";
import { LIFESTYLE_STEP } from "./lifestyle.ts";
import { LOCATION_STEP } from "./location.ts";
import { ownersStep } from "./owners.ts";
import { ROOMS_STEP } from "./rooms.ts";
import { TECHNICAL_STEP } from "./technical.ts";
import {
  AGENT_STEPS,
  type AgentStep,
  type EntityDef,
  type FieldDef,
  type PropertyType,
  type StepSchema,
} from "./types.ts";

export * from "./types.ts";

const SCHEMAS: Record<AgentStep, StepSchema> = {
  owners: ownersStep(VOICE_DEFAULTS.coOwnerNames),
  location: LOCATION_STEP,
  context: CONTEXT_STEP,
  technical: TECHNICAL_STEP,
  rooms: ROOMS_STEP,
  lifestyle: LIFESTYLE_STEP,
};

export function isStep(value: unknown): value is AgentStep {
  return typeof value === "string" && (AGENT_STEPS as readonly string[]).includes(value);
}

export function stepSchema(step: AgentStep): StepSchema {
  return SCHEMAS[step];
}

/** Property types of the V4 "Night" audit (the app's
 * `PropertyTypeProfile.voiceAudit`). */
export const VOICE_AUDIT_TYPES: readonly PropertyType[] = ["maison", "appartement", "autre"];

/** The voiced steps of [type] (plan §2.8; null: not chosen yet, every
 * step), like the app's `PropertyTypeProfile.voiceSteps` (parity fixture
 * tests/fixtures/property_type_profiles.json). */
export function voiceStepsFor(type: string | null): AgentStep[] {
  if (type === null) return [...AGENT_STEPS];
  const known = type as PropertyType;
  if (!VOICE_DEFAULTS.allTypes && !VOICE_AUDIT_TYPES.includes(known)) return [];
  return AGENT_STEPS.filter((step) => SCHEMAS[step].voiceTypes.includes(known));
}

/** The type deciding which fields are asked: the type not chosen yet
 * counts as a house (the app's undecided profile asks the dwelling
 * questions). */
export function effectiveType(values: Record<string, unknown>): PropertyType {
  return (values.property_type ?? "maison") as PropertyType;
}

/** The codes [field] offers for this property (a list may be narrower
 * for some types). */
export function codesOf(field: FieldDef, values: Record<string, unknown>): Record<string, string> {
  const kind = field.kind;
  if (kind.type !== "enum" && kind.type !== "list") return {};
  const allowed = field.codesFor?.[effectiveType(values)];
  if (!allowed) return kind.codes;
  return Object.fromEntries(Object.entries(kind.codes).filter(([code]) => allowed.includes(code)));
}

/** Whether [field] is asked for this property (type and current answers,
 * e.g. pool fields only once a pool is known). */
export function isAsked(field: FieldDef, values: Record<string, unknown>): boolean {
  if (field.types && !field.types.includes(effectiveType(values))) return false;
  switch (field.condition) {
    case "heat_pump":
      return Array.isArray(values.heating_systems) && values.heating_systems.includes("pac");
    case "pool":
      return Array.isArray(values.outdoor_equipment) &&
        values.outdoor_equipment.includes("piscine");
    default:
      return true;
  }
}

export function fieldOf(step: AgentStep, column: string): FieldDef | undefined {
  return SCHEMAS[step].fields.find((field) => field.column === column);
}

export function entityOf(step: AgentStep, name: string): EntityDef | undefined {
  return SCHEMAS[step].entities.find((entity) => entity.name === name);
}

/** The step owning a `properties` column (for "out of step" answers). */
export function stepOfColumn(column: string): { step: AgentStep; field: FieldDef } | null {
  for (const step of AGENT_STEPS) {
    const field = fieldOf(step, column);
    if (field) return { step, field };
  }
  return null;
}

/** French names of the steps (replies, "out of step" pills). */
export const STEP_LABELS: Record<AgentStep, string> = {
  owners: "Propriétaires",
  location: "Adresse",
  context: "Contexte",
  technical: "Technique",
  rooms: "Pièces",
  lifestyle: "Cadre de vie",
};
