// Types of the step registry of the voice agent (plan §4.4): each tunnel
// step declares the `properties` columns the agent may fill, its entities
// (rooms, previous estimates, co-owners), its instructions and its output.

export type AgentStep =
  | "owners"
  | "location"
  | "context"
  | "technical"
  | "rooms"
  | "lifestyle";

export const AGENT_STEPS: readonly AgentStep[] = [
  "owners",
  "location",
  "context",
  "technical",
  "rooms",
  "lifestyle",
];

export type PropertyType =
  | "maison"
  | "appartement"
  | "terrain"
  | "stationnement"
  | "dependance"
  | "local_commercial"
  | "immeuble"
  | "autre";

export const PROPERTY_TYPES: readonly PropertyType[] = [
  "maison",
  "appartement",
  "terrain",
  "stationnement",
  "dependance",
  "local_commercial",
  "immeuble",
  "autre",
];

export type FieldKind =
  | { type: "year"; min: number }
  | { type: "decimal"; min: number; max: number; exclusiveMin?: boolean }
  | { type: "int"; min: number; max: number }
  /** Whole euros. */
  | { type: "money"; min: number; max: number }
  /** A past month, "mm/aaaa" or "aaaa-mm" → "aaaa-mm-01". */
  | { type: "month"; minYear: number }
  | { type: "bool" }
  | { type: "enum"; codes: Record<string, string> }
  /** Several codes; [exclusive] (e.g. "aucune") excludes the others. */
  | { type: "list"; codes: Record<string, string>; exclusive?: string }
  /** Free text. [coverage]: its words must have been said (plan §4.2);
   * [suggestion]: proposed to the seller, never applied (secret note). */
  | { type: "text"; max: number; coverage?: boolean; suggestion?: boolean }
  /** Surface of a room: a number, or two dimensions ("4 x 3"). */
  | { type: "area"; min: number; max: number };

/** Lexical anchors: per code (or "*" for any value), normalized stems one
 * of which must start a word of the quote. */
export type Anchors = Record<string, readonly string[]>;

export interface FieldDef {
  column: string;
  /** French name (question topic, pills "Assainissement ?"). */
  label: string;
  kind: FieldKind;
  /** Property types asking it (all when omitted). The type not chosen yet
   * counts as a house (the app's undecided profile). */
  types?: readonly PropertyType[];
  /** Asked only once another answer is known. */
  condition?: "heat_pump" | "pool";
  /** Codes offered per type (a list restricted for some types). */
  codesFor?: Partial<Record<PropertyType, readonly string[]>>;
  anchors?: Anchors;
  /** Numbers must be in the quote (default for numeric kinds). */
  numericAnchor?: boolean;
  /** Required for these property types (screen rules, prompt order). */
  requiredFor?: readonly PropertyType[];
}

export type EntityName = "room" | "previous_estimate" | "co_owner";

export interface EntityDef {
  name: EntityName;
  /** French name ("pièce"). */
  label: string;
  /** Short reference prefix given in the prompt ("R" → R1, R2…). */
  refPrefix: string;
  fields: FieldDef[];
  /** Most entities of this kind on the dossier. */
  max: number;
  ops: readonly ("create" | "update" | "delete")[];
}

export interface StepSchema {
  step: AgentStep;
  /** French description of the step (prompt). */
  title: string;
  fields: FieldDef[];
  entities: EntityDef[];
  /** Step-specific instructions (prompt). */
  instructions: string[];
  /** Property types this step is voiced for (plan §2.8). */
  voiceTypes: readonly PropertyType[];
  /** Output budget of one answer (retried once with twice as much). */
  maxTokens: number;
  /** The step classifies lifestyle items (V6). */
  lifestyle?: boolean;
  /** The transcript holds identity data: wiped from the journal once the
   * turn is answered (V1). */
  identity?: boolean;
}
