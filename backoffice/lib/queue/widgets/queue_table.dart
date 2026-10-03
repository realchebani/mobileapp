import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_backoffice/queue/widgets/status_chip.dart';
import 'package:realesty_ui/realesty_ui.dart';

const _flex = [14, 22, 10, 10, 13, 20, 18];

/// The queue as a table; dossiers of a lot follow each other with a green
/// bar on their left.
class QueueTable extends StatelessWidget {
  const new({
    required this.rows,
    required this.onOpen,
    required this.onTake,
    required this.onAssign,
    this.canAssign = false,
    this.busyId,
    super.key,
  });

  final List<DossierSummary> rows;
  final ValueChanged<DossierSummary> onOpen;
  final ValueChanged<DossierSummary> onTake;
  final ValueChanged<DossierSummary> onAssign;
  final bool canAssign;
  final String? busyId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final header = RealestyTextStyles.caption.copyWith(color: c.texteDiscret);
    final titles = [
      l10n.queueColSubmitted,
      l10n.queueColProperty,
      l10n.queueColSeller,
      l10n.queueColStatus,
      l10n.queueColAssignee,
      l10n.queueColFlags,
      l10n.queueColActions,
    ];
    return BoCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RealestySpacing.lg,
              vertical: RealestySpacing.sm,
            ),
            child: Row(
              children: [
                for (var i = 0; i < titles.length; i++)
                  Expanded(
                    flex: _flex[i],
                    child: Text(titles[i].toUpperCase(), style: header),
                  ),
              ],
            ),
          ),
          for (final row in rows) ...[
            Divider(height: 1, color: c.ligne),
            _QueueRow(
              row: row,
              busy: busyId == row.id,
              canAssign: canAssign,
              onOpen: () => onOpen(row),
              onTake: () => onTake(row),
              onAssign: () => onAssign(row),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const new({
    required this.row,
    required this.busy,
    required this.canAssign,
    required this.onOpen,
    required this.onTake,
    required this.onAssign,
  });

  final DossierSummary row;
  final bool busy;
  final bool canAssign;
  final VoidCallback onOpen;
  final VoidCallback onTake;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final small = RealestyTextStyles.bodySmall.copyWith(color: c.encre2);
    final strong = RealestyTextStyles.label.copyWith(color: c.encre);
    final submittedAt = row.submittedAt;
    final age = submittedAt == null
        ? null
        : DateTime.now().difference(submittedAt);
    final late =
        age != null &&
        age.inHours > 48 &&
        row.status == DossierStatus.submitted;
    final type = propertyTypeLabel(
      l10n,
      row.propertyType,
      row.propertyTypeOther,
    );
    final area = row.areaM2;

    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: row.lot == null ? Colors.transparent : c.vert,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: RealestySpacing.lg,
          vertical: RealestySpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              flex: _flex[0],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submittedAt == null ? '—' : dateTimeFr(submittedAt),
                    style: strong,
                  ),
                  if (age != null)
                    Text(
                      late
                          ? '${_age(l10n, age)} · ${l10n.queueAgeAlert}'
                          : _age(l10n, age),
                      style: small.copyWith(color: late ? c.erreur : null),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: _flex[1],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [type, if (area != null) squareMeters(area)].join(' · '),
                    style: strong,
                  ),
                  Text(
                    [row.city, row.postcode].whereType<String>().join(' '),
                    style: small,
                  ),
                  if (row.lot != null) ...[
                    const SizedBox(height: RealestySpacing.xxs),
                    BoChip(
                      l10n.queueLot(row.lot!.name),
                      color: c.vertTexte,
                      background: c.vertTeinte,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: _flex[2],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.ownerInitials ?? '—', style: strong),
                  if (row.ownerDeactivated)
                    BoChip(
                      l10n.queueSellerDeactivated,
                      color: c.erreur,
                      background: c.erreurFond,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: _flex[3],
              child: Align(
                alignment: Alignment.centerLeft,
                child: DossierStatusChip(row.status),
              ),
            ),
            Expanded(
              flex: _flex[4],
              child: Text(
                row.assignedTo?.displayName ?? l10n.queueUnassigned,
                style: row.assignedTo == null
                    ? small.copyWith(color: c.texteDiscret)
                    : small,
              ),
            ),
            Expanded(
              flex: _flex[5],
              child: Wrap(
                spacing: RealestySpacing.xxs,
                runSpacing: RealestySpacing.xxs,
                children: [
                  if (row.documentsToVerify > 0)
                    BoChip(
                      l10n.queueDocsToVerify(row.documentsToVerify),
                      color: c.attention,
                      background: c.attentionFond,
                    ),
                  if (row.documentsAddedAfter > 0)
                    BoChip(l10n.queueDocsAfter(row.documentsAddedAfter)),
                  BoChip(l10n.queuePhotos(row.photosCount)),
                  if (row.hasVoice) BoChip(l10n.queueVoice),
                  if (row.draftStatus ==
                      ValuationDraftStatus.submittedForApproval)
                    BoChip(
                      l10n.queueDraftSubmitted,
                      color: c.expert,
                      background: c.expertFond,
                    )
                  else if (row.draftVersion != null)
                    BoChip(l10n.queueDraft(row.draftVersion!)),
                ],
              ),
            ),
            Expanded(
              flex: _flex[6],
              child: busy
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Wrap(
                      spacing: RealestySpacing.xxs,
                      children: [
                        TextButton(
                          onPressed: onOpen,
                          child: Text(l10n.queueOpen),
                        ),
                        if (row.status == DossierStatus.submitted)
                          TextButton(
                            onPressed: onTake,
                            child: Text(l10n.queueTake),
                          ),
                        if (canAssign && row.status != DossierStatus.certified)
                          TextButton(
                            onPressed: onAssign,
                            child: Text(l10n.queueAssign),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _age(AppLocalizations l10n, Duration age) => age.inHours < 24
      ? l10n.queueAgeHours(age.inHours)
      : l10n.queueAgeDays(age.inDays);
}
