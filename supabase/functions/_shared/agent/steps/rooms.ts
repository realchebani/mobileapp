// V5c · dictée des pièces: rooms created, changed or removed by voice
// (entity `room`, short references R1…R40 of the table the app sends).
// Names, numbering, matching and the habitable total: ../rooms.ts.

import type { EntityDef, StepSchema } from "./types.ts";

export const ROOM_LEVELS = {
  sous_sol: "Sous-sol",
  rdc: "RDC",
  etage_1: "Étage 1",
  etage_2: "Étage 2",
  combles: "Combles",
};

export const FLOOR_COVERINGS = {
  parquet_chene: "Parquet chêne",
  parquet: "Parquet",
  carrelage: "Carrelage",
  moquette: "Moquette",
  beton_cire: "Béton ciré",
  stratifie: "Stratifié",
  vinyle: "Vinyle",
  autre: "Autre",
};

export const GLAZINGS = {
  simple: "Simple vitrage",
  double: "Double vitrage",
  triple: "Triple vitrage",
};

export const ROOM_ENTITY: EntityDef = {
  name: "room",
  label: "pièce",
  refPrefix: "R",
  fields: [
    { column: "name", label: "Pièce", kind: { type: "text", max: 60 } },
    { column: "area_m2", label: "Surface", kind: { type: "area", min: 0.5, max: 500 } },
    {
      column: "level",
      label: "Niveau",
      kind: { type: "enum", codes: ROOM_LEVELS },
      anchors: {
        sous_sol: ["sous sol", "cave", "en dessous"],
        rdc: ["rez de chaussee", "rdc", "rez", "en bas", "plain pied"],
        etage_1: ["etage", "premier", "1er", "en haut", "haut", "dessus", "1 er"],
        etage_2: ["deuxieme", "second", "2e", "2eme", "2 eme", "2nd", "dernier etage"],
        combles: ["comble", "grenier", "mansard", "sous les toits", "sous toiture"],
      },
    },
    {
      column: "floor_covering",
      label: "Sol",
      kind: { type: "enum", codes: FLOOR_COVERINGS },
      anchors: {
        parquet_chene: ["chene"],
        parquet: ["parquet", "plancher", "bois"],
        carrelage: ["carrel", "carreau", "faience", "gres"],
        moquette: ["moquette"],
        beton_cire: ["beton"],
        stratifie: ["stratifi", "flottant"],
        vinyle: ["vinyl", "lino", "pvc", "sol souple"],
      },
    },
    {
      column: "glazing",
      label: "Vitrage",
      kind: { type: "enum", codes: GLAZINGS },
      // The kind of glazing AND a window word: "double" alone is ambiguous
      // (checked in rooms.ts).
      anchors: {
        simple: ["simple"],
        double: ["double", "doubles"],
        triple: ["triple", "triples"],
      },
    },
    {
      column: "ceiling_height_m",
      label: "Hauteur sous plafond",
      kind: { type: "decimal", min: 1.5, max: 6 },
    },
    {
      column: "description",
      label: "Description",
      kind: { type: "text", max: 300, coverage: true },
    },
  ],
  max: 40,
  ops: ["create", "update", "delete"],
};

export const ROOMS_STEP: StepSchema = {
  step: "rooms",
  title: "dictée des pièces (tableau des surfaces)",
  fields: [],
  entities: [ROOM_ENTITY],
  instructions: [
    'Une entité "room" par pièce dite. Plusieurs pièces dans une phrase = plusieurs entités ; un niveau ou un sol dit une fois pour une liste vaut pour chacune (même citation).',
    '"name" : le nom de la pièce tel que dit (Séjour, Cuisine, Chambre, Salle de bain, Salle d’eau, WC, Entrée, Bureau, Dégagement, Cellier, Buanderie, Garage, Sous-sol, ou un autre nom court) ; ne numérote pas les chambres (l’application le fait).',
    '"area_m2" : la surface en m² ; si le vendeur donne deux dimensions (« 4 sur 3 »), écris-les « 4x3 ».',
    '"level" seulement s’il est dit : ne le déduis jamais.',
    '"description" : ce qui caractérise la pièce, reformulé au minimum, factuel, sans adjectif ni chiffre ajouté, sans nom de personne (300 caractères au plus).',
    'Modifier ou supprimer une pièce existante : op update / delete, "target" = sa référence (R1…) et "target_quote" = les mots exacts qui la désignent. « Même sol que le séjour » : "copy_from" = la référence du séjour et "copy_fields" = les champs copiés, avec "copy_quote".',
    "Ne parle pas des surfaces totales : l’application les calcule. Réplique très courte (une phrase), sans question si le vendeur enchaîne les pièces.",
  ],
  voiceTypes: ["maison", "appartement", "autre"],
  maxTokens: 2500,
};
