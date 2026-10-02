// V3 · Contexte & type de bien: the type and its precision (EPIC-13), the
// purchase, the reason for the sale and the previous agency estimates
// (entity `previous_estimate`). Bounds of the screen
// (PropertyContextState): years from 1900, amounts 1 000 € – 100 M€.

import type { EntityDef, FieldDef, StepSchema } from "./types.ts";
import { PROPERTY_TYPES } from "./types.ts";

export const PROPERTY_TYPE_LABELS: Record<string, string> = {
  maison: "Maison",
  appartement: "Appartement",
  terrain: "Terrain",
  stationnement: "Garage / parking",
  dependance: "Cave / dépendance",
  local_commercial: "Local commercial",
  immeuble: "Immeuble",
  autre: "Autre",
};

export const CONTEXT_FIELDS: FieldDef[] = [
  {
    column: "property_type",
    label: "Type",
    kind: { type: "enum", codes: PROPERTY_TYPE_LABELS },
    anchors: {
      maison: ["maison", "pavillon", "villa", "longere", "ferme", "mas", "chalet", "bastide"],
      appartement: [
        "appartement",
        "appart",
        "studio",
        "duplex",
        "triplex",
        "loft",
        "t1",
        "t2",
        "t3",
        "t4",
        "t5",
        "f1",
        "f2",
        "f3",
        "f4",
        "f5",
      ],
      terrain: ["terrain", "parcelle", "champ", "pre", "bois"],
      stationnement: ["garage", "box", "parking", "place", "stationnement"],
      dependance: [
        "cave",
        "cellier",
        "grange",
        "atelier",
        "depend",
        "remise",
        "hangar",
        "grenier",
        "chai",
        "ecurie",
        "abri",
      ],
      local_commercial: [
        "boutique",
        "bureau",
        "commerce",
        "local",
        "magasin",
        "restaurant",
        "entrepot",
        "cabinet",
        "atelier",
        "commercial",
      ],
      immeuble: ["immeuble", "batiment", "logements", "appartements"],
    },
  },
  {
    column: "property_type_other",
    label: "Précision",
    kind: { type: "text", max: 100, coverage: true },
    types: ["dependance", "autre"],
  },
  {
    column: "land_kind",
    label: "Terrain",
    kind: {
      type: "enum",
      codes: {
        constructible: "Constructible",
        non_constructible: "Non constructible",
        inconnu: "Je ne sais pas",
      },
    },
    types: ["terrain"],
    anchors: {
      constructible: ["constructible", "batir", "viabilis"],
      non_constructible: [
        "non constructible",
        "pas constructible",
        "inconstructible",
        "agricole",
        "naturel",
      ],
      inconnu: ["sais pas", "sait pas", "inconnu", "aucune idee", "je ne sais", "pas sur"],
    },
  },
  {
    column: "parking_kind",
    label: "Stationnement",
    kind: {
      type: "enum",
      codes: {
        box: "Box",
        garage: "Garage",
        place_couverte: "Place couverte",
        place_exterieure: "Place extérieure",
      },
    },
    types: ["stationnement"],
    anchors: {
      box: ["box"],
      garage: ["garage"],
      place_couverte: ["couvert", "sous abri", "sous sol", "souterrain", "abrite"],
      place_exterieure: ["exterieur", "dehors", "plein air", "aerien", "air libre", "decouvert"],
    },
  },
  {
    column: "commercial_use",
    label: "Usage",
    kind: { type: "text", max: 100, coverage: true },
    types: ["local_commercial"],
  },
  {
    column: "units_count",
    label: "Logements",
    kind: { type: "int", min: 2, max: 500 },
    types: ["immeuble"],
  },
  {
    column: "purchase_year",
    label: "Achat",
    kind: { type: "year", min: 1900 },
  },
  {
    column: "purchase_price_eur",
    label: "Prix d’achat",
    kind: { type: "money", min: 1000, max: 100_000_000 },
  },
  {
    column: "self_built",
    label: "Construit par vous",
    kind: { type: "bool" },
    types: ["maison", "appartement", "dependance", "autre"],
    anchors: {
      "*": ["constru", "bati", "bat", "achet", "acquis", "herit", "fait faire", "plans"],
    },
  },
  {
    column: "sale_reason",
    label: "Raison",
    kind: {
      type: "enum",
      codes: {
        mutation: "Mutation",
        agrandissement: "Agrandissement",
        separation: "Séparation",
        investissement: "Investissement",
        autre: "Autre",
      },
    },
    anchors: {
      mutation: ["mutation", "mute", "demenag", "travail", "boulot", "emploi", "poste", "region"],
      agrandissement: [
        "plus grand",
        "agrandi",
        "famille",
        "enfant",
        "bebe",
        "place",
        "trop petit",
        "pieces en plus",
      ],
      separation: ["separ", "divorc", "rupture", "quitte"],
      investissement: ["investiss", "locatif", "placement", "rentab", "location"],
    },
  },
  {
    column: "previously_estimated",
    label: "Déjà estimé",
    kind: { type: "bool" },
    anchors: {
      "*": ["estim", "evalu", "agence", "agent", "notaire", "expert", "avis de valeur", "jamais"],
    },
  },
];

export const PREVIOUS_ESTIMATE_ENTITY: EntityDef = {
  name: "previous_estimate",
  label: "estimation précédente",
  refPrefix: "E",
  fields: [
    {
      column: "price_eur",
      label: "Estimation",
      kind: { type: "money", min: 1000, max: 100_000_000 },
    },
    { column: "estimated_month", label: "Mois", kind: { type: "month", minYear: 1900 } },
    {
      column: "agency_name",
      label: "Agence",
      kind: { type: "text", max: 120, coverage: true },
    },
  ],
  max: 5,
  ops: ["create", "update", "delete"],
};

export const CONTEXT_STEP: StepSchema = {
  step: "context",
  title: "contexte de la vente et type de bien",
  fields: CONTEXT_FIELDS,
  entities: [PREVIOUS_ESTIMATE_ENTITY],
  instructions: [
    'Un changement de type de bien ("property_type") ne se fait que s’il est dit clairement ; il sera confirmé par le vendeur.',
    'Une estimation d’agence = une entité "previous_estimate" (prix en euros, mois au format mm/aaaa s’il est dit, nom de l’agence s’il est dit) ; "previously_estimated" vaut true dès qu’une estimation est dite, false si le vendeur dit qu’il n’y en a jamais eu.',
    "Prix : la valeur en euros entiers (« 320 000 », « trois cent vingt mille » ou « 320 k » → 320000).",
  ],
  voiceTypes: PROPERTY_TYPES,
  maxTokens: 1500,
};
