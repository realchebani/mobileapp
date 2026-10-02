/// EPIC-14 · default answers to the open questions of the plan
/// (docs/plans/2026-10-02-voix-etendue.md, « Choix par défaut en attendant
/// le porteur de projet »): the recommended option of each, kept here so
/// that a different decision is a one-line change. The Edge Functions
/// mirror theirs in `supabase/functions/_shared/agent/defaults.ts`.
abstract final class VoiceDefaults {
  /// Q1 (b): V1 takes the co-owners' names by voice (always confirmed);
  /// false = (a), only the ownership type.
  static const coOwnerNames = true;

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
}
