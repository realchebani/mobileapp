// V1 · Propriétaires: single or several owners and, when the owner chose
// it (Q1, VOICE_DEFAULTS.coOwnerNames), the co-owners' first and last
// names (always confirmed: proper names are unreliable in STT). Phone and
// e-mail stay on screen. The transcript is wiped from the journal once
// the turn is answered.

import type { EntityDef, FieldDef, StepSchema } from "./types.ts";
import { PROPERTY_TYPES } from "./types.ts";

export const OWNERS_FIELDS: FieldDef[] = [
  {
    column: "ownership_type",
    label: "Propriétaires",
    kind: {
      type: "enum",
      codes: { single: "Unique propriétaire", multiple: "Plusieurs propriétaires" },
    },
    anchors: {
      single: ["seul", "seule", "unique", "moi meme", "uniquement moi", "juste moi", "que moi"],
      multiple: [
        "plusieurs",
        "indivision",
        "couple",
        "mari",
        "femme",
        "epou",
        "conjoint",
        "compagn",
        "frere",
        "soeur",
        "enfant",
        "parent",
        "nous",
        "on est",
        "a deux",
        "a trois",
        "a quatre",
        "copropri",
        "co propri",
        "associe",
        "sci",
        "avec",
        "deux",
        "trois",
      ],
    },
  },
];

export const CO_OWNER_ENTITY: EntityDef = {
  name: "co_owner",
  label: "co-propriétaire",
  refPrefix: "P",
  fields: [
    { column: "first_name", label: "Prénom", kind: { type: "text", max: 100 } },
    { column: "last_name", label: "Nom", kind: { type: "text", max: 100 } },
  ],
  max: 10,
  ops: ["create"],
};

export function ownersStep(coOwnerNames: boolean): StepSchema {
  return {
    step: "owners",
    title: "propriétaires du bien",
    fields: OWNERS_FIELDS,
    entities: coOwnerNames ? [CO_OWNER_ENTITY] : [],
    instructions: coOwnerNames
      ? [
        'Note les prénoms et noms des co-propriétaires ("co_owner", opération create) tels qu’ils sont entendus, sans corriger l’orthographe ; un nom par champ, la citation exacte de chacun.',
        "Ne demande jamais de téléphone, d’e-mail, d’adresse ni de date de naissance : ils se saisissent à l’écran.",
      ]
      : [
        "Ne note aucun nom de personne ; ne demande jamais de téléphone, d’e-mail ni d’adresse.",
      ],
    voiceTypes: PROPERTY_TYPES,
    maxTokens: 1200,
    identity: true,
  };
}
