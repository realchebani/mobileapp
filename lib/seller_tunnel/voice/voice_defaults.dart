/// EPIC-14 · default answers to the open questions of the plan
/// (docs/plans/2026-10-02-voix-etendue.md, « Choix par défaut en attendant
/// le porteur de projet »): the recommended option of each, kept here so
/// that a different decision is a one-line change. The Edge Functions
/// mirror theirs in `supabase/functions/_shared/agent/defaults.ts`.
abstract final class VoiceDefaults {
  /// Q2 (a): the V2 address is dictated (transcription only) into the
  /// search field.
  static const addressDictation = true;

  /// Q4 (a): the V4b microphone opens the step sheet; the V4 "Night" audit
  /// stays behind a "Conversation guidée" link.
  static const technicalSheet = true;

  /// Q5 (a): the agent speaks in the step sheets, is silent while rooms
  /// are dictated (text and a vibration), and speaks the final summary.
  static const silentRoomsDictation = true;

  /// Q8 (a): V5 "Dicter mes pièces" stores the `manual` measurement
  /// method (the rooms themselves get `source = voice`).
  static const dictationIsManualMethod = true;

  /// Q12 (a): step sheets for every type of property; false = (b), voice
  /// only where the V4 "Night" audit is offered.
  static const allTypes = true;

  // EPIC-16 · « Voix prioritaire » (docs/plans/2026-10-03-voix-prioritaire.md
  // §15, « Choix par défaut en attendant le porteur de projet »). V1 has no
  // voice (owner decision).

  /// Q1 (a): voice-first steps open the modal step sheet by themselves;
  /// « Écrire plutôt » closes it.
  static const voiceFirst = true;

  /// Q2 (a): the sheet opened by itself listens at once (consent and
  /// microphone given), except on a step already complete.
  static const autoListen = true;

  /// Q3 (a): « Écrire plutôt » is remembered for the whole device.
  static const inputModePerDevice = true;

  /// Q4 (a): a value said for a validated step is proposed as an update
  /// (« a → b ? Oui · Non ») in the sheet; entities wait « À confirmer » on
  /// their step.
  static const updateValidatedSteps = true;

  /// Q5 (a): V7 lists the answers still to confirm without blocking.
  static const pendingBlocksSubmission = false;

  /// Q7 (a): « Notes complémentaires » on V2, V3, V4b, V5c and V6.
  static const stepNotes = true;

  /// After a network failure of a voice session, the sheet does not open
  /// by itself for this long.
  static const offlinePause = Duration(minutes: 10);
}
