// The step registry of the voice agent: one StepSchema per tunnel step
// (plan §4.4), and the rules shared by validation and prompt (which field
// is asked for which property, which step is voiced for which type).

import { VOICE_DEFAULTS } from "../defaults.ts";
import { CONTEXT_STEP, PREVIOUS_ESTIMATE_ENTITY } from "./context.ts";
import { LIFESTYLE_STEP } from "./lifestyle.ts";
import { LOCATION_STEP } from "./location.ts";
import { ROOM_ENTITY, ROOMS_STEP } from "./rooms.ts";
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
  location: "Adresse",
  context: "Contexte",
  technical: "Technique",
  rooms: "Pièces",
  lifestyle: "Cadre de vie",
};

/** Columns never pre-filled from another step (plan §3.2, Q6 bis): the
 * type is structuring (chosen on V3 only) and the secret note is the
 * seller's own words for the expert. The address and the parcels are not
 * agent fields at all, and V1 has no voice. */
export const NEVER_PREFILLED: readonly string[] = ["property_type", "secret_note"];

export interface CrossStepField {
  step: AgentStep;
  field: FieldDef;
}

export interface CrossStepEntity {
  step: AgentStep;
  entity: EntityDef;
}

/** What may be said on [step] for another step (plan §3.2): the fields of
 * the other voiced steps asked for this type (conditional ones included:
 * they may come with their condition), new rooms and previous estimates,
 * lifestyle items, and a note for each of those steps. The app mirrors it
 * in `PropertyTypeProfile.prefillTargets` (parity fixture). */
export interface CrossStepTargets {
  fields: CrossStepField[];
  entities: CrossStepEntity[];
  lifestyle: boolean;
  noteSteps: AgentStep[];
}

export function crossStepTargets(
  step: AgentStep,
  values: Record<string, unknown>,
): CrossStepTargets {
  const type = (values.property_type ?? null) as string | null;
  const others = voiceStepsFor(type).filter((other) => other !== step);
  if (!VOICE_DEFAULTS.crossStepPrefill) {
    return { fields: [], entities: [], lifestyle: false, noteSteps: [] };
  }
  const assumed = { ...values, heating_systems: ["pac"], outdoor_equipment: ["piscine"] };
  const fields = others.flatMap((other) =>
    SCHEMAS[other].fields
      .filter((field) => !NEVER_PREFILLED.includes(field.column) && isAsked(field, assumed))
      .map((field) => ({ step: other, field }))
  );
  const entities: CrossStepEntity[] = [];
  if (others.includes("context")) {
    entities.push({ step: "context", entity: PREVIOUS_ESTIMATE_ENTITY });
  }
  if (others.includes("rooms")) entities.push({ step: "rooms", entity: ROOM_ENTITY });
  return {
    fields,
    entities,
    lifestyle: others.includes("lifestyle"),
    noteSteps: VOICE_DEFAULTS.stepNotes ? others : [],
  };
}
