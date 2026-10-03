import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Status of a dossier: Envoyé (amber), En examen (green tint), Certifié.
class DossierStatusChip extends StatelessWidget {
  const new(this.status, {super.key});

  final DossierStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final (color, background) = switch (status) {
      DossierStatus.submitted => (c.attention, c.attentionFond),
      DossierStatus.inReview => (c.vertTexte, c.vertTeinte),
      DossierStatus.certified => (c.surface, c.vert),
      DossierStatus.draft => (c.encre2, c.surface2),
    };
    return BoChip(
      status.label(context.l10n),
      color: color,
      background: background,
    );
  }
}
