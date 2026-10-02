// V6 · Cadre de vie: noise, overlooking and the secret note (a suggestion
// only), plus the assets and watch points (`lifestyle_items`, validated in
// validate.ts). Noise and overlooking only where the screen asks them
// (`asksNeighbourhood`: not for commercial premises).

import type { FieldDef, PropertyType, StepSchema } from "./types.ts";

const NEIGHBOURHOOD: PropertyType[] = ["maison", "appartement", "terrain", "immeuble", "autre"];

const overlooking = { aucun: "Aucun", leger: "Léger", important: "Important" };

export const LIFESTYLE_FIELDS: FieldDef[] = [
  {
    column: "noise_level",
    label: "Bruit",
    kind: { type: "int", min: 1, max: 10 },
    types: NEIGHBOURHOOD,
    // A judgement ("très calme" → 2), not a number said.
    numericAnchor: false,
  },
  {
    column: "overlooking",
    label: "Vis-à-vis",
    kind: { type: "enum", codes: overlooking },
    types: NEIGHBOURHOOD,
    anchors: {
      aucun: ["aucun", "pas de vis", "sans vis", "pas vis", "personne", "pas de voisin", "isole"],
      leger: ["leger", "un peu", "peu", "petit", "partiel"],
      important: ["important", "beaucoup", "fort", "en face", "direct", "plein", "gros"],
    },
  },
  {
    column: "secret_note",
    label: "Note secrète",
    kind: { type: "text", max: 500, suggestion: true },
  },
];

/** Lifestyle item limits (`lifestyle_items` checks, V6 rules). */
export const LIFESTYLE_ITEM_MIN = 3;
export const LIFESTYLE_ITEM_MAX = 140;
export const LIFESTYLE_ITEMS_PER_KIND = 10;

export const LIFESTYLE_STEP: StepSchema = {
  step: "lifestyle",
  title: "cadre de vie (quartier, environnement)",
  fields: LIFESTYLE_FIELDS,
  entities: [],
  instructions: [
    'Classe ce qui est dit sur le quartier et l’environnement en atouts ("asset") et points de vigilance ("watch_point") dans "lifestyle_items", UN élément par fait distinct (ne regroupe pas plusieurs faits dans un même libellé), avec un libellé court et factuel (140 caractères au plus) reformulé à la troisième personne, et la citation exacte.',
    '"noise_level" de 1 (très calme) à 10 (très bruyant) seulement si le vendeur qualifie le bruit ; "overlooking" dès qu’il parle de vis-à-vis (y compris « aucun vis-à-vis » → aucun).',
    '"secret_note" seulement s’il exprime une information qu’il souhaite garder pour l’expert (ex. motivation, contrainte de calendrier).',
  ],
  voiceTypes: [...NEIGHBOURHOOD, "local_commercial"],
  maxTokens: 1500,
  lifestyle: true,
};
