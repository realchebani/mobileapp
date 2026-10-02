import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/photos/models/room_photo_suggestions.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Pour de bonnes photos": how to take photos useful to the expert (and
/// to the listing), with the instruction "Personne dans le champ".
class PhotoTipsCard extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    Widget tip(RealestyIcons icon, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RealestySpacing.xs,
      children: [
        RealestyIcon(icon, size: 18, color: c.vertTexte),
        Expanded(
          child: Text(
            text,
            style: RealestyTextStyles.listSubtitle.copyWith(
              height: 1.45,
              color: c.encre,
            ),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(RealestyRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          Text(
            l10n.photosTipsTitle,
            style: RealestyTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
              color: c.encre,
            ),
          ),
          tip(RealestyIcons.target, l10n.photosTipAngle),
          tip(RealestyIcons.spark, l10n.photosTipLight),
          tip(RealestyIcons.users, l10n.photosTipPeople),
          tip(RealestyIcons.search, l10n.photosTipDefects),
        ],
      ),
    );
  }
}

/// "Suggestions de l’IA": what the vision AI proposes for the room, each
/// value applied only on "Appliquer" / "Ajouter à la description"; the
/// personal items to put away and the photos with a person.
class PhotoSuggestionsCard extends StatelessWidget {
  const new({
    required this.suggestions,
    required this.analyzing,
    required this.failedCount,
    required this.appliedCount,
    required this.onApplyKind,
    required this.onApplyCovering,
    required this.onApplyGlazing,
    required this.onAddNote,
    required this.onRetry,
    super.key,
  });

  final RoomPhotoSuggestions suggestions;

  /// Photos being analysed.
  final int analyzing;

  /// Photos whose analysis failed.
  final int failedCount;

  /// Suggestions applied on this visit.
  final int appliedCount;

  final ValueChanged<RoomSuggestion>? onApplyKind;
  final ValueChanged<FloorCovering>? onApplyCovering;
  final ValueChanged<Glazing>? onApplyGlazing;
  final ValueChanged<String>? onAddNote;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final s = suggestions;
    Widget proposal(String text, String action, VoidCallback? onPressed) => Row(
      spacing: RealestySpacing.xs,
      children: [
        Expanded(
          child: Text(
            text,
            style: RealestyTextStyles.listTitle.copyWith(color: c.encre),
          ),
        ),
        RealestyButton(
          label: action,
          variant: RealestyButtonVariant.secondary,
          height: 36,
          expand: false,
          onPressed: onPressed,
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.sm,
        children: [
          Row(
            spacing: RealestySpacing.xs,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.photosSuggestionsTitle,
                    style: RealestyTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.encre,
                    ),
                  ),
                ),
              ),
              ProvenanceTag(
                ProvenanceKind.aiEstimated,
                label: l10n.photosSuggestionsTag,
              ),
            ],
          ),
          if (analyzing > 0)
            Row(
              spacing: RealestySpacing.xs,
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.vertTexte,
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.photosSuggestionsWaiting(analyzing),
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                ),
              ],
            ),
          if (s.kind case final kind?)
            proposal(
              l10n.photosSuggestionKind(kind.label(l10n)),
              l10n.photosSuggestionApply,
              onApplyKind == null ? null : () => onApplyKind!(kind),
            ),
          if (s.floorCovering case final covering?)
            proposal(
              l10n.photosSuggestionCovering(covering.label(l10n)),
              l10n.photosSuggestionApply,
              onApplyCovering == null ? null : () => onApplyCovering!(covering),
            ),
          if (s.glazing case final glazing?)
            proposal(
              l10n.photosSuggestionGlazing(glazing.label(l10n)),
              l10n.photosSuggestionApply,
              onApplyGlazing == null ? null : () => onApplyGlazing!(glazing),
            ),
          for (final note in s.conditionNotes)
            proposal(
              note,
              l10n.photosSuggestionNote,
              onAddNote == null ? null : () => onAddNote!(note),
            ),
          if (!s.hasProposals && analyzing == 0 && s.analyzedCount > 0)
            Text(
              l10n.photosSuggestionsNone,
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.texteDiscret,
              ),
            ),
          if (s.peoplePhotoIds.isNotEmpty)
            InlineBanner(
              message: l10n.photosPeopleWarning(s.peoplePhotoIds.length),
              icon: RealestyIcons.warning,
            ),
          if (s.personalItems.isNotEmpty)
            InlineBanner(
              message: l10n.photosPersonalItems(s.personalItems.join(', ')),
              variant: InlineBannerVariant.info,
              icon: RealestyIcons.eye,
            ),
          if (failedCount > 0)
            Row(
              spacing: RealestySpacing.xs,
              children: [
                Expanded(
                  child: Text(
                    l10n.photosAnalysisFailed(failedCount),
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.erreur,
                    ),
                  ),
                ),
                RealestyButton(
                  label: l10n.photosRetry,
                  variant: RealestyButtonVariant.text,
                  height: 36,
                  expand: false,
                  onPressed: onRetry,
                ),
              ],
            ),
          if (appliedCount > 0)
            Text(
              l10n.photosSuggestionsApplied(appliedCount),
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.vertTexte,
              ),
            ),
        ],
      ),
    );
  }
}
