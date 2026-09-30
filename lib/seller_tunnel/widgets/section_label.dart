import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

/// "Légende" section label (spec 0.5): 12/700 uppercase, Texte discret —
/// e.g. "Propriétaire 1 · vous", "Type de bien".
class SectionLabel extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: RealestyTextStyles.caption.copyWith(
          color: context.realestyColors.texteDiscret,
        ),
      ),
    );
  }
}

/// "Titre 2" section title (Sora 18/600), used by V4b and V6 — e.g.
/// "Carte d’identité", "Atouts".
class SectionTitle extends StatelessWidget {
  const new(this.text, {this.trailing, super.key});

  final String text;

  /// Optional widget after the title (e.g. a count badge).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: RealestySpacing.xs,
      children: [
        Flexible(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: RealestyTextStyles.title2.copyWith(
                color: context.realestyColors.encre,
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
