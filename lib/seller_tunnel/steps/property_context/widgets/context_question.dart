import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// A labelled question of V3 (label 13/600 Encre 2 over its [child]), with
/// an optional error message below, styled like `RealestyTextField`'s.
class ContextQuestion extends StatelessWidget {
  const new({
    required this.label,
    required this.child,
    this.errorText,
    this.spacing = 6,
    this.tag,
    super.key,
  });

  final String label;
  final Widget child;
  final String? errorText;

  /// Gap between the label, [child] and the error.
  final double spacing;

  /// « Dicté » (answered by voice on this visit) or « À confirmer » (said
  /// on another step, EPIC-16).
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: spacing,
        children: [
          Row(
            spacing: RealestySpacing.xs,
            children: [
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: RealestyTextStyles.label.copyWith(color: c.encre2),
                  ),
                ),
              ),
              ?tag,
            ],
          ),
          child,
          if (errorText != null) ContextErrorText(errorText!),
        ],
      ),
    );
  }
}

/// Error message of a V3 answer (info icon + 13 Erreur text).
class ContextErrorText extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: RealestyIcon(
              RealestyIcons.infoCircle,
              size: 14,
              color: c.erreur,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: RealestyTextStyles.fieldError.copyWith(color: c.erreur),
            ),
          ),
        ],
      ),
    );
  }
}
