import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';

/// Step progress: [total] segments (height 4, gap 4), the first [completed]
/// in Vert texte, the rest in Ligne.
class SegmentedProgress extends StatelessWidget {
  const new({
    required this.total,
    required this.completed,
    this.semanticLabel,
    super.key,
  }) : assert(total > 0, 'total must be positive');

  final int total;
  final int completed;

  /// Announced label, e.g. "Étape 2 sur 5". Defaults to "completed / total".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      label: semanticLabel ?? '$completed / $total',
      child: ExcludeSemantics(
        child: Row(
          spacing: RealestySpacing.xxs,
          children: [
            for (var i = 0; i < total; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: RealestyMotion.short,
                  curve: RealestyMotion.shortCurve,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < completed ? c.vertTexte : c.ligne,
                    borderRadius: BorderRadius.circular(
                      RealestyRadius.progress,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
