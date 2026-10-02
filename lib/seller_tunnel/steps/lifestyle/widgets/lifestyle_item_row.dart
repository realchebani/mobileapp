import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/models/lifestyle_item_draft.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// An asset (green check) or watch point (warning colors) on V6, with the
/// edit pen; tapping the row opens its edit sheet.
class LifestyleItemRow extends StatelessWidget {
  const new({required this.item, required this.onEdit, super.key});

  final LifestyleItemDraft item;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final isAsset = item.kind == LifestyleItemKind.asset;
    return RealestyPressable(
      onPressed: onEdit,
      semanticLabel: context.l10n.lifestyleEditItem(item.label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.field),
          border: Border.all(color: c.bordureCarte),
        ),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAsset ? c.vertTeinte : c.attentionFond,
              ),
              child: RealestyIcon(
                isAsset ? RealestyIcons.check : RealestyIcons.warning,
                size: 16,
                color: isAsset ? c.vertTexte : c.attention,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    item.label,
                    style: RealestyTextStyles.bubble.copyWith(color: c.encre),
                  ),
                  if (item.fromVoice)
                    Row(
                      spacing: 4,
                      children: [
                        RealestyIcon(
                          RealestyIcons.mic,
                          size: 12,
                          color: c.vertTexte,
                        ),
                        Text(
                          context.l10n.lifestyleVoiceAdded,
                          style: RealestyTextStyles.badge.copyWith(
                            color: c.vertTexte,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            RealestyIcon(RealestyIcons.pen, size: 16, color: c.texteDiscret),
          ],
        ),
      ),
    );
  }
}
