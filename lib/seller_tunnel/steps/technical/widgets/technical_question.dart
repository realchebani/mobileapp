import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// A labelled question of V4b (label 13/600 Encre 2 over its [child], gap
/// 8), with an optional error message and [footer] below.
class TechnicalQuestion extends StatelessWidget {
  const new({
    required this.label,
    required this.child,
    this.errorText,
    this.footer,
    super.key,
  });

  final String label;
  final Widget child;
  final String? errorText;

  /// E.g. a provenance tag.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: RealestySpacing.xs,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: RealestyTextStyles.label.copyWith(color: c.encre2),
            ),
          ),
          child,
          if (errorText != null) TechnicalErrorText(errorText!),
          ?footer,
        ],
      ),
    );
  }
}

/// Error message of a V4b answer (info icon + 13 Erreur text), styled like
/// `RealestyTextField`'s.
class TechnicalErrorText extends StatelessWidget {
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

/// The [ProvenanceTag] of a [provenance], left-aligned.
class TechnicalProvenanceTag extends StatelessWidget {
  const new(this.provenance, {super.key});

  final Provenance provenance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (kind, label) = switch (provenance) {
      Provenance.declared => (
        ProvenanceKind.declared,
        l10n.technicalProvenanceDeclared,
      ),
      Provenance.document => (
        ProvenanceKind.document,
        l10n.technicalProvenanceDocument,
      ),
      Provenance.external => (
        ProvenanceKind.externalSource,
        l10n.technicalProvenanceExternal,
      ),
      Provenance.expert => (
        ProvenanceKind.expertVerified,
        l10n.technicalProvenanceExpert,
      ),
      Provenance.ai => (ProvenanceKind.aiEstimated, l10n.technicalProvenanceAi),
    };
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ProvenanceTag(kind, label: label),
    );
  }
}
