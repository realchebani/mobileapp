import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Label · value · tags (provenance, « À vérifier »).
class FieldRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    this.tags = const [],
    this.detail,
    super.key,
  });

  final String label;
  final String value;
  final List<Widget> tags;

  /// A second line (quote of the seller, contact…).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RealestySpacing.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.ligne)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 260,
            child: Text(
              label,
              style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: RealestyTextStyles.label),
                if (detail != null)
                  Text(
                    detail!,
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.texteDiscret,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          if (tags.isNotEmpty)
            Wrap(spacing: RealestySpacing.xxs, children: tags),
        ],
      ),
    );
  }
}

/// A warning tag (« À vérifier »).
class WarningChip extends StatelessWidget {
  const new(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return BoChip(label, color: c.erreur, background: c.erreurFond);
  }
}
