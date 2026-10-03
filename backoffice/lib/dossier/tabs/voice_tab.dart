import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/tabs/synthesis_tab.dart';
import 'package:realesty_backoffice/dossier/widgets/dossier_labels.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// What the seller said (EPIC-16): the fill sheet with the original quotes,
/// then the conversation, step by step.
class VoiceTab extends StatelessWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final said = [
      for (final row in dossier.fillSheet)
        if (row.quote != null || row.confirmed == false) row,
    ];
    if (dossier.voiceThread.isEmpty && said.isEmpty) {
      return BoMessage(title: l10n.voiceNone, body: l10n.voiceIntro);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.voiceIntro,
          style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
        ),
        const SizedBox(height: RealestySpacing.md),
        BoCard(
          title: l10n.voiceFillSheet,
          child: Column(
            children: [
              for (final row in said)
                FieldRow(
                  label: [
                    stepLabel(l10n, row.step),
                    ?row.entityLabel,
                    row.label,
                  ].join(' · '),
                  value: row.value ?? '—',
                  detail: row.quote == null
                      ? null
                      : l10n.voiceQuote(row.quote!),
                  tags: fillSheetTags(l10n, row),
                ),
            ],
          ),
        ),
        const SizedBox(height: RealestySpacing.md),
        BoCard(
          title: l10n.voiceThread,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final turn in dossier.voiceThread) _TurnTile(turn: turn),
            ],
          ),
        ),
      ],
    );
  }
}

class _TurnTile extends StatelessWidget {
  const new({required this.turn});

  final VoiceTurn turn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final strike = turn.undone ? TextDecoration.lineThrough : null;
    final small = RealestyTextStyles.bodySmall.copyWith(
      color: c.encre2,
      decoration: strike,
    );
    final retained = {...turn.retained}..remove('evidence');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RealestySpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.ligne)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              stepLabel(l10n, turn.step),
              if (turn.at != null) dateTimeFr(turn.at!),
            ].join(' · '),
            style: RealestyTextStyles.caption.copyWith(color: c.texteDiscret),
          ),
          if (turn.undone) WarningChip(l10n.voiceUndone),
          if (turn.transcript != null)
            Text(
              '${l10n.voiceSeller} : ${turn.transcript}',
              style: RealestyTextStyles.body.copyWith(decoration: strike),
            ),
          if (turn.reply != null)
            Text('${l10n.voiceAgent} : ${turn.reply}', style: small),
          if (retained.values.any(_present))
            Text(l10n.voiceRetained(compactJson(retained)), style: small),
          if (turn.rejected.isNotEmpty)
            Text(l10n.voiceRejected(compactJson(turn.rejected)), style: small),
          if (turn.crossStep.isNotEmpty)
            Text(
              l10n.voiceCrossStep(compactJson(turn.crossStep)),
              style: small,
            ),
          if (turn.error != null)
            Text(turn.error!, style: small.copyWith(color: c.erreur)),
        ],
      ),
    );
  }

  static bool _present(Object? value) => switch (value) {
    null => false,
    final Map<dynamic, dynamic> map => map.isNotEmpty,
    final List<dynamic> list => list.isNotEmpty,
    _ => true,
  };
}
