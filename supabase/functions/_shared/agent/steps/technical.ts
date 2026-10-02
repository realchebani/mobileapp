// V4 audit vocal and V4b · Audit technique: the same columns, codes and
// rules as the screen, per type of property (EPIC-13 `technicalFields`,
// parity fixture tests/fixtures/property_type_profiles.json).

import type { FieldDef, PropertyType, StepSchema } from "./types.ts";

const DWELLING: PropertyType[] = ["maison", "appartement", "autre"];
const HOUSE: PropertyType[] = ["maison", "autre"];

const exposure = {
  nord: "Nord",
  nord_est: "Nord-Est",
  est: "Est",
  sud_est: "Sud-Est",
  sud: "Sud",
  sud_ouest: "Sud-Ouest",
  ouest: "Ouest",
  nord_ouest: "Nord-Ouest",
  traversant: "Traversant",
};

const levels = { plain_pied: "Plain-pied", r1: "R+1", r2_plus: "R+2 et plus" };

const wallMaterial = {
  parpaing: "Parpaing",
  brique: "Brique",
  pierre: "Pierre",
  beton: "Béton",
  moellon: "Moellon",
  bois: "Bois",
  pise: "Pisé",
};

const adjacency = {
  independant: "Indépendant",
  "1": "Mitoyen 1 côté",
  "2": "Mitoyen 2 côtés",
  "3": "Mitoyen 3 côtés",
};

const roofType = {
  tuiles: "Tuiles",
  ardoises: "Ardoises",
  toit_terrasse: "Toit-terrasse",
  bac_acier: "Bac acier",
  zinc: "Zinc",
  autre: "Autre",
};

const heatingSystems = {
  electricite: "Électrique",
  pac: "Pompe à chaleur",
  gaz: "Gaz",
  fioul: "Fioul",
  bois: "Poêle à bois",
  granules: "Poêle à granulés",
  cheminee: "Cheminée / insert",
  reseau_chaleur: "Réseau de chaleur",
  solaire: "Solaire",
  autre: "Autre",
};

const heatPumpType = {
  air_eau: "Air / eau",
  air_air: "Air / air",
  geothermique: "Géothermique",
};

const sanitation = {
  tout_a_l_egout: "Tout-à-l’égout",
  fosse_septique: "Fosse septique",
  puits_perdu: "Puits perdu",
};

const outdoorEquipment = {
  piscine: "Piscine",
  garage: "Garage",
  terrasse: "Terrasse",
  abri_jardin: "Abri de jardin",
  portail_motorise: "Portail motorisé",
};

const poolType = {
  enterree_liner: "Enterrée · liner",
  enterree_coque: "Enterrée · coque",
  enterree_beton: "Enterrée · béton",
  semi_enterree: "Semi-enterrée",
  hors_sol: "Hors-sol",
};

const parkingLevel = {
  sous_sol: "Sous-sol",
  rdc: "Rez-de-chaussée",
  etage: "Étage",
  exterieur: "Extérieur",
};

const parkingFeatures = {
  porte_motorisee: "Porte motorisée",
  electricite: "Électricité",
  borne_recharge: "Borne de recharge",
  eau: "Point d’eau",
  acces_securise: "Accès sécurisé",
};

export const TECHNICAL_FIELDS: FieldDef[] = [
  {
    column: "construction_year",
    label: "Construction",
    kind: { type: "year", min: 1600 },
    types: ["maison", "appartement", "dependance", "local_commercial", "immeuble", "autre"],
    requiredFor: ["maison", "appartement", "autre", "immeuble"],
  },
  {
    column: "living_area_m2",
    label: "Surface habitable",
    kind: { type: "decimal", min: 5, max: 2000 },
    types: DWELLING,
    requiredFor: DWELLING,
  },
  {
    column: "living_room_area_m2",
    label: "Surface séjour",
    kind: { type: "decimal", min: 1, max: 2000 },
    types: DWELLING,
  },
  {
    column: "rooms_count",
    label: "Pièces",
    kind: { type: "int", min: 1, max: 30 },
    types: DWELLING,
  },
  {
    column: "bedrooms_count",
    label: "Chambres",
    kind: { type: "int", min: 0, max: 30 },
    types: DWELLING,
  },
  {
    column: "levels",
    label: "Niveaux",
    kind: { type: "enum", codes: levels },
    types: HOUSE,
    requiredFor: ["maison"],
    anchors: {
      plain_pied: ["plain pied", "un seul niveau", "pas d etage", "sans etage", "rez de chaussee"],
      r1: ["r 1", "un etage", "1 etage", "etage", "deux niveaux", "2 niveaux", "duplex"],
      r2_plus: [
        "r 2",
        "deux etages",
        "2 etages",
        "trois etages",
        "3 etages",
        "trois niveaux",
        "3 niveaux",
        "plusieurs etages",
        "quatre niveaux",
        "triplex",
      ],
    },
  },
  {
    column: "orientation",
    label: "Exposition",
    kind: { type: "enum", codes: exposure },
    types: DWELLING,
    anchors: {
      nord: ["nord"],
      nord_est: ["nord est"],
      est: ["est", "levant"],
      sud_est: ["sud est"],
      sud: ["sud", "midi", "plein sud"],
      sud_ouest: ["sud ouest"],
      ouest: ["ouest", "couchant"],
      nord_ouest: ["nord ouest"],
      traversant: ["traversant", "double exposition", "deux cotes", "des deux cotes"],
    },
  },
  {
    column: "wall_material",
    label: "Murs",
    kind: { type: "enum", codes: wallMaterial },
    types: ["maison", "appartement", "immeuble", "autre"],
    anchors: {
      parpaing: ["parpaing"],
      brique: ["brique"],
      pierre: ["pierre"],
      beton: ["beton", "banche"],
      moellon: ["moellon"],
      bois: ["bois", "ossature"],
      pise: ["pise", "terre"],
    },
  },
  {
    column: "adjacency",
    label: "Mitoyenneté",
    kind: { type: "enum", codes: adjacency },
    types: HOUSE,
    anchors: {
      independant: [
        "independant",
        "isole",
        "pas mitoyen",
        "non mitoyen",
        "aucun mitoyen",
        "pas de mitoyen",
        "detache",
        "aucun voisin",
      ],
      "1": ["mitoyen", "un cote", "1 cote", "jumel", "accole"],
      "2": ["mitoyen", "deux cotes", "2 cotes", "en bande", "accole"],
      "3": ["mitoyen", "trois cotes", "3 cotes"],
    },
  },
  {
    column: "roof_type",
    label: "Toiture",
    kind: { type: "enum", codes: roofType },
    types: ["maison", "immeuble", "autre"],
    anchors: {
      tuiles: ["tuile"],
      ardoises: ["ardoise"],
      toit_terrasse: ["terrasse", "toit plat", "toiture plate", "plat"],
      bac_acier: ["bac acier", "acier", "tole"],
      zinc: ["zinc"],
    },
  },
  {
    column: "roof_year",
    label: "Année toiture",
    kind: { type: "year", min: 1600 },
    types: ["maison", "immeuble", "autre"],
  },
  {
    column: "heating_systems",
    label: "Chauffage",
    kind: { type: "list", codes: heatingSystems },
    types: ["maison", "appartement", "local_commercial", "immeuble", "autre"],
    requiredFor: ["maison", "appartement"],
    anchors: {
      electricite: ["electri", "radiateur", "convecteur", "grille pain", "inertie"],
      pac: [
        "pompe a chaleur",
        "pompes a chaleur",
        "pac",
        "clim reversible",
        "climatisation reversible",
        "aerotherm",
        "geotherm",
      ],
      gaz: ["gaz"],
      fioul: ["fioul", "fuel", "mazout"],
      bois: ["bois", "buche", "poele"],
      granules: ["granule", "pellet"],
      cheminee: ["chemine", "insert", "foyer"],
      reseau_chaleur: ["reseau", "chauffage urbain", "chauffage collectif", "collectif"],
      solaire: ["solaire", "panneau"],
    },
  },
  {
    column: "heat_pump_type",
    label: "Type de PAC",
    kind: { type: "enum", codes: heatPumpType },
    types: ["maison", "appartement", "local_commercial", "immeuble", "autre"],
    condition: "heat_pump",
    anchors: {
      air_eau: ["air eau", "eau"],
      air_air: ["air air", "clim", "split", "soufflant"],
      geothermique: ["geotherm", "sol", "sous sol", "forage", "captage"],
    },
  },
  {
    column: "heat_pump_year",
    label: "Année PAC",
    kind: { type: "year", min: 1900 },
    types: ["maison", "appartement", "local_commercial", "immeuble", "autre"],
    condition: "heat_pump",
  },
  {
    column: "sanitation",
    label: "Assainissement",
    kind: { type: "enum", codes: sanitation },
    types: ["maison", "appartement", "terrain", "immeuble", "autre"],
    anchors: {
      tout_a_l_egout: [
        "tout a l egout",
        "egout",
        "reseau collectif",
        "assainissement collectif",
        "collectif",
        "raccorde",
        "mairie",
      ],
      fosse_septique: [
        "fosse",
        "septique",
        "micro station",
        "microstation",
        "assainissement individuel",
        "assainissement autonome",
        "individuel",
        "autonome",
        "spanc",
      ],
      puits_perdu: ["puits perdu", "puisard", "puits"],
    },
  },
  {
    column: "outdoor_equipment",
    label: "Extérieur",
    kind: { type: "list", codes: outdoorEquipment },
    types: ["maison", "appartement", "terrain", "autre"],
    anchors: {
      piscine: ["piscine", "bassin"],
      garage: ["garage"],
      terrasse: ["terrasse"],
      abri_jardin: ["abri", "cabane", "remise", "cabanon"],
      portail_motorise: ["portail"],
    },
  },
  {
    column: "pool_type",
    label: "Type de piscine",
    kind: { type: "enum", codes: poolType },
    types: ["maison", "appartement", "terrain", "autre"],
    condition: "pool",
    anchors: {
      enterree_liner: ["liner"],
      enterree_coque: ["coque", "polyester"],
      enterree_beton: ["beton", "maconn", "carrel"],
      semi_enterree: ["semi"],
      hors_sol: ["hors sol", "tubulaire", "gonflable"],
    },
  },
  {
    column: "pool_length_m",
    label: "Longueur piscine",
    kind: { type: "decimal", min: 0, max: 999.99, exclusiveMin: true },
    types: ["maison", "appartement", "terrain", "autre"],
    condition: "pool",
  },
  {
    column: "pool_width_m",
    label: "Largeur piscine",
    kind: { type: "decimal", min: 0, max: 999.99, exclusiveMin: true },
    types: ["maison", "appartement", "terrain", "autre"],
    condition: "pool",
  },
  {
    column: "usable_area_m2",
    label: "Surface utile",
    kind: { type: "decimal", min: 1, max: 2000 },
    types: ["stationnement", "dependance", "local_commercial"],
    requiredFor: ["local_commercial"],
  },
  {
    column: "parking_level",
    label: "Niveau",
    kind: { type: "enum", codes: parkingLevel },
    types: ["stationnement"],
    anchors: {
      sous_sol: ["sous sol", "souterrain", "niveau moins", "moins un", "moins deux", "en dessous"],
      rdc: ["rez de chaussee", "rdc", "plain pied", "niveau de la rue", "au sol", "en bas"],
      etage: ["etage", "en hauteur", "niveau un", "niveau deux", "premier niveau"],
      exterieur: ["exterieur", "dehors", "plein air", "aerien", "air libre", "en surface"],
    },
  },
  {
    column: "parking_features",
    label: "Équipements",
    kind: { type: "list", codes: parkingFeatures },
    types: ["stationnement", "dependance"],
    codesFor: { dependance: ["electricite", "eau"] },
    anchors: {
      porte_motorisee: ["porte motoris", "porte automatique", "motoris", "telecommande"],
      electricite: ["electri", "prise", "courant", "eclairage", "lumiere"],
      borne_recharge: ["borne", "recharge", "wallbox"],
      eau: ["eau", "robinet"],
      acces_securise: ["securis", "badge", "bip", "digicode", "portail", "ferme a cle", "ferme"],
    },
  },
];

export const TECHNICAL_STEP: StepSchema = {
  step: "technical",
  title: "audit technique du bien",
  fields: TECHNICAL_FIELDS,
  entities: [],
  instructions: [],
  voiceTypes: [
    "maison",
    "appartement",
    "terrain",
    "stationnement",
    "dependance",
    "local_commercial",
    "immeuble",
    "autre",
  ],
  maxTokens: 1500,
};
