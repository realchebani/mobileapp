import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_header.dart';
import 'package:mobileapp/ui/ui.dart';

/// Root of a seller space tab that later epics fill (Visites: EPIC-09,
/// Coffre-fort: EPIC-11): its title and a "Bientôt" message.
class ComingSoonPage extends StatelessWidget {
  const new({
    required this.title,
    required this.message,
    required this.icon,
    super.key,
  });

  /// The "Visites" tab (V13, EPIC-09).
  factory visits(BuildContext context) => ComingSoonPage(
    title: context.l10n.visitsTitle,
    message: context.l10n.visitsComingSoon,
    icon: RealestyIcons.calendar,
  );

  /// The "Coffre-fort" tab (C1, EPIC-11).
  factory vault(BuildContext context) => ComingSoonPage(
    title: context.l10n.vaultTitle,
    message: context.l10n.vaultComingSoon,
    icon: RealestyIcons.vault,
  );

  final String title;
  final String message;
  final RealestyIcons icon;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return ColoredBox(
      color: c.ivoire,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            RealestySpacing.gutter,
            RealestySpacing.md,
            RealestySpacing.gutter,
            RealestySpacing.xl,
          ),
          children: [
            SellerSpaceTitle(title),
            const SizedBox(height: RealestySpacing.xl),
            SellerSpaceCard(
              padding: const EdgeInsets.all(RealestySpacing.xl),
              child: Column(
                spacing: RealestySpacing.sm,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.vertTeinte,
                      shape: BoxShape.circle,
                    ),
                    child: RealestyIcon(icon, size: 28, color: c.vertTexte),
                  ),
                  RealestyBadge(label: context.l10n.comingSoonBadge),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: RealestyTextStyles.body.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
