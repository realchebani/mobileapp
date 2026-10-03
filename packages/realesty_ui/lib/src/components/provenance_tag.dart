import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// Where a piece of data comes from ("every data shows its provenance").
enum ProvenanceKind {
  /// Déclaré — typed or said by the user.
  declared('Déclaré'),

  /// Extrait d'un document — read from an uploaded document.
  document('Extrait d’un document'),

  /// Source externe — cadastre, DVF, public data…
  externalSource('Source externe'),

  /// Vérifié expert — validated by a Realesty expert.
  expertVerified('Vérifié expert'),

  /// Estimé IA — estimated by the AI, not yet verified.
  aiEstimated('Estimé IA');

  new(this.defaultLabel);

  /// French label shown by default.
  final String defaultLabel;
}

/// Small provenance tag (height 20, radius 6, 11/700).
class ProvenanceTag extends StatelessWidget {
  const new(this.kind, {this.label, super.key});

  final ProvenanceKind kind;

  /// Overrides [ProvenanceKind.defaultLabel] (e.g. for localization).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final (Color background, Color foreground) = switch (kind) {
      ProvenanceKind.declared => (c.surface2, c.encre2),
      ProvenanceKind.document ||
      ProvenanceKind.externalSource => (c.expertFond, c.expert),
      ProvenanceKind.expertVerified => (c.vertTeinte, c.vertTexte),
      ProvenanceKind.aiEstimated => (c.attentionFond, c.attention),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RealestyRadius.tag),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label ?? kind.defaultLabel,
          maxLines: 1,
          style: RealestyTextStyles.tag.copyWith(color: foreground),
        ),
      ),
    );
  }
}
