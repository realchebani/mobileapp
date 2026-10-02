// EPIC-14 · default answers to the open questions of the plan
// (docs/plans/2026-10-02-voix-etendue.md §12, section « Choix par défaut en
// attendant le porteur de projet »): the recommended option of each, kept
// here so that a different decision is a one-line change. The app mirrors
// the ones it needs in lib/seller_tunnel/voice/voice_defaults.dart.

export const VOICE_DEFAULTS = {
  /** Q1 (b): V1 takes the number of owners and the co-owners' names
   * (always confirmed, not kept in the journal); false = (a), nothing by
   * voice on V1 except the ownership type. */
  coOwnerNames: true,
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
} as const;
