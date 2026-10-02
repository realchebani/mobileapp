import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// Lets the seller pick, among [candidates], a property to add to a lot;
/// returns it, or null when dismissed.
Future<Property?> showLotMemberSheet(
  BuildContext context, {
  required List<Property> candidates,
}) {
  return showModalBottomSheet<Property>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.realestyColors.ivoire,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RealestyRadius.sheet),
      ),
    ),
    builder: (context) => LotMemberSheet(candidates: candidates),
  );
}

/// The properties that can join a lot; pops with the tapped one.
class LotMemberSheet extends StatelessWidget {
  const new({required this.candidates, super.key});

  final List<Property> candidates;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.lg,
          RealestySpacing.gutter,
          RealestySpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            Text(
              l10n.lotAddTitle,
              style: RealestyTextStyles.title2.copyWith(color: c.encre),
            ),
            if (candidates.isEmpty)
              Text(
                l10n.lotNoCandidate,
                style: RealestyTextStyles.body.copyWith(color: c.texteDiscret),
              ),
            for (final (index, property) in candidates.indexed)
              RealestyListItem(
                title: propertyShortLabel(l10n, property),
                subtitle: propertyStatusLabel(l10n, property),
                leadingIcon: propertyTypeIcon(property.propertyType),
                showDivider: index < candidates.length - 1,
                onTap: () => Navigator.of(context).pop(property),
              ),
          ],
        ),
      ),
    );
  }
}
