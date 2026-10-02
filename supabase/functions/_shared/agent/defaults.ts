// EPIC-14 · default answers to the open questions of the plan
// (docs/plans/2026-10-02-voix-etendue.md §12, section « Choix par défaut en
// attendant le porteur de projet »): the recommended option of each, kept
// here so that a different decision is a one-line change. The app mirrors
// the ones it needs in lib/seller_tunnel/voice/voice_defaults.dart.

export const VOICE_DEFAULTS = {
  /** Q2 (a): the address is dictated (transcription only, never sent to
   * the language model) into the search field. */
  addressDictation: true,
  /** Q6 (a): answers are applied at once (undoable); only risky changes
   * are confirmed. Answers with a confidence in [confirmFrom, MIN) are
   * confirmed rather than asked again. */
  confirmFrom: 0.5,
  /** Q6 (a): a value replacing a known one by more than this asks a
   * confirmation (surface ±50 %, year ±20 years). */
  strongChange: { ratio: 0.5, years: 20 },
  /** Q10 (a): "4 sur 3" gives a 12 m² room (both numbers in the quote). */
  areaFromDimensions: true,
  /** Q12 (a): step sheets for every type of property (the V4 "Night"
   * audit stays for dwellings); false = (b), voice only for maison /
   * appartement / autre. */
  allTypes: true,

  // EPIC-16 · « Voix prioritaire » (docs/plans/2026-10-03-voix-prioritaire.md
  // §15, « Choix par défaut en attendant le porteur de projet »). V1 has no
  // voice at all (owner decision): the `owners` step is gone.

  /** Owner decision: what is said for another step is stored as a pending
   * answer and pre-filled there « À confirmer »; false = the EPIC-14
   * behaviour (grey "out of step" pills, nothing kept). */
  crossStepPrefill: true,
  /** Q7 (a): « Notes complémentaires » per step (and per room). */
  stepNotes: true,
  /** Q13 (a): a pending answer needs this confidence (0,5–0,7 is kept with
   * a « ? » in its pill); (b) would be 0.7. */
  crossStepMinConfidence: 0.5,
  /** Answers for other steps kept from one turn (plan §3.3). */
  crossStepMax: 8,
  /** Open pending answers per property (plan §3.3). */
  pendingMax: 100,
  /** Q14 (a): the compact catalog of the other steps (fields, formats,
   * codes of the type) goes into a second cacheable system block. */
  crossStepCatalog: true,
} as const;
