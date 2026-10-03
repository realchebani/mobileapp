import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_badge.dart';
import 'package:realesty_ui/src/icons/realesty_icon.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// A formula of V10 (L’Essentiel, Le Premium, L’Expert): badge and tagline,
/// name, rate (Sora) "au succès", fees, the estimated commission and the
/// included features with checks.
class OfferPlanCard extends StatelessWidget {
  const new({
    required this.badgeLabel,
    required this.badgeVariant,
    required this.tagline,
    required this.name,
    required this.rate,
    required this.rateCaption,
    required this.features,
    this.fees,
    this.commission,
    super.key,
  });

  final String badgeLabel;
  final RealestyBadgeVariant badgeVariant;

  /// e.g. "L’autonomie accompagnée".
  final String tagline;

  /// e.g. "L’Essentiel".
  final String name;

  /// e.g. "1 %".
  final String rate;

  /// e.g. "au succès".
  final String rateCaption;

  /// e.g. "Aucun frais de dossier · aucun abonnement".
  final String? fees;

  /// e.g. "Soit ~5 250 € de commission…".
  final String? commission;
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final fees = this.fees;
    final commission = this.commission;
    return Container(
      padding: const EdgeInsets.all(RealestySpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.all(color: c.bordureCarte),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: RealestySpacing.xs,
            runSpacing: RealestySpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              RealestyBadge(label: badgeLabel, variant: badgeVariant),
              Text(
                tagline,
                style: RealestyTextStyles.label.copyWith(color: c.texteDiscret),
              ),
            ],
          ),
          const SizedBox(height: RealestySpacing.sm),
          Text(name, style: RealestyTextStyles.title2.copyWith(color: c.encre)),
          const SizedBox(height: RealestySpacing.xxs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: RealestySpacing.xs,
            children: [
              Text(
                rate,
                style: RealestyTextStyles.display.copyWith(color: c.encre),
              ),
              Text(
                rateCaption,
                style: RealestyTextStyles.bodySmall.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            ],
          ),
          if (fees != null)
            Text(
              fees,
              style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
            ),
          if (commission != null) ...[
            const SizedBox(height: RealestySpacing.xs),
            Text(
              commission,
              style: RealestyTextStyles.bodySmall.copyWith(
                color: c.vertTexte,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: RealestySpacing.sm),
          Divider(height: 1, color: c.ligne),
          const SizedBox(height: RealestySpacing.sm),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: RealestySpacing.xs,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: RealestyIcon(
                      RealestyIcons.check,
                      size: 16,
                      color: c.vertTexte,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      feature,
                      style: RealestyTextStyles.bodySmall.copyWith(
                        color: c.encre2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
