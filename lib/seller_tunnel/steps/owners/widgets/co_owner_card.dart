import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:mobileapp/seller_tunnel/voice/widgets/step_voice_sheet.dart';
import 'package:mobileapp/ui/ui.dart';

/// A co-owner on V1: initials, name, "Co-propriétaire · 06 98 76 54 32" and
/// the edit button (deleting is done from the edit sheet). A dictated
/// co-owner is tagged "Dicté"; an incomplete one asks to be completed.
class CoOwnerCard extends StatelessWidget {
  const new({
    required this.coOwner,
    required this.onEdit,
    this.dictated = false,
    this.incomplete = false,
    super.key,
  });

  final OwnerDraft coOwner;
  final VoidCallback? onEdit;
  final bool dictated;

  /// Missing answers (a dictated co-owner has no phone yet).
  final bool incomplete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final name = coOwner.fullName;
    // Normalized, and kept on one line.
    final phone = displayPhone(
      phoneToE164(coOwner.phone) ?? coOwner.phone.trim(),
    ).replaceAll(' ', noBreakSpace);
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Row(
        spacing: RealestySpacing.sm,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surface2,
              ),
              child: Text(
                coOwner.initials,
                style: RealestyTextStyles.segment.copyWith(
                  fontFamily: RealestyFonts.sora,
                  color: c.encre,
                ),
              ),
            ),
          ),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: RealestySpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        name,
                        style: RealestyTextStyles.listTitle.copyWith(
                          color: c.encre,
                        ),
                      ),
                      if (dictated) const DictatedTag(),
                    ],
                  ),
                  Text(
                    incomplete
                        ? l10n.ownersCoOwnerIncomplete
                        : phone.isEmpty
                        ? l10n.ownersCoOwnerRole
                        : l10n.ownersCoOwnerSubtitle(phone),
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: incomplete ? c.erreur : c.texteDiscret,
                    ),
                  ),
                ],
              ),
            ),
          ),
          RealestyIconButton(
            icon: RealestyIcons.pen,
            semanticLabel: l10n.ownersEditCoOwner(name),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
