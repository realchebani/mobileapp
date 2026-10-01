import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// A measurement method of V5: icon tile, title with an optional badge and
/// description; the whole card is tappable. [highlighted] is the suggested
/// method (green border and tile).
class MethodCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
    this.highlighted = false,
    this.isLoading = false,
    super.key,
  });

  final RealestyIcons icon;
  final String title;
  final String description;

  /// Tap callback; null disables the card.
  final VoidCallback? onTap;

  /// Shown after the title (e.g. "Bientôt").
  final Widget? badge;

  final bool highlighted;

  /// Shows a spinner instead of the badge (the choice is being saved).
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return RealestyPressable(
      onPressed: onTap,
      // Not faded while its choice is being saved.
      showDisabled: !isLoading,
      child: Container(
        padding: const EdgeInsets.all(RealestySpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(RealestyRadius.bubble),
          border: Border.all(
            color: highlighted ? c.vertTexte : c.bordureCarte,
            width: RealestyBorders.medium,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 14,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highlighted ? c.vertTeinte : c.surface2,
                borderRadius: BorderRadius.circular(RealestyRadius.button),
              ),
              child: RealestyIcon(
                icon,
                size: 24,
                color: highlighted ? c.vertTexte : c.encre,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: RealestySpacing.xxs,
                children: [
                  Row(
                    spacing: RealestySpacing.xs,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: RealestyTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                            color: c.encre,
                          ),
                        ),
                      ),
                      if (isLoading)
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.vertTexte,
                          ),
                        )
                      else
                        ?badge,
                    ],
                  ),
                  Text(
                    description,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      height: 1.45,
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
