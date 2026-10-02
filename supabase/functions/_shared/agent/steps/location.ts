// V2 · Géoloc & cadastre: only the special situations go to the agent.
// The address is dictated (transcription only, `agent-transcribe`
// mode=dictation: never sent to the language model) and the parcels are
// chosen on the map.

import type { FieldDef, StepSchema } from "./types.ts";
import { PROPERTY_TYPES } from "./types.ts";

export const LOCATION_FIELDS: FieldDef[] = [
  {
    column: "special_situations",
    label: "Situations particulières",
    kind: {
      type: "list",
      codes: {
        servitude_passage: "Servitude de passage",
        servitude_reseaux: "Servitude de réseaux",
        autre: "Autre situation",
        aucune: "Aucune",
      },
      exclusive: "aucune",
    },
    anchors: {
      servitude_passage: ["passage", "chemin", "acces", "passer"],
      servitude_reseaux: [
        "reseau",
        "canalis",
        "ligne",
        "cable",
        "conduite",
        "tuyau",
        "egout",
        "gaz",
        "electri",
        "eau",
      ],
      aucune: ["aucun", "pas de servitude", "rien", "sans servitude", "pas de situation", "non"],
    },
  },
  {
    column: "special_situation_other",
    label: "Autre situation",
    kind: { type: "text", max: 300, coverage: true },
  },
];

export const LOCATION_STEP: StepSchema = {
  step: "location",
  title: "situations particulières de la parcelle (servitudes)",
  fields: LOCATION_FIELDS,
  entities: [],
  instructions: [
    "L’adresse et les parcelles ne sont pas traitées ici : n’en parle pas et ne les demande pas.",
    '"special_situations" : aucune exclut les autres. "special_situation_other" seulement pour une situation qui n’est ni une servitude de passage ni de réseaux, avec le code autre.',
  ],
  voiceTypes: PROPERTY_TYPES,
  maxTokens: 1000,
};
