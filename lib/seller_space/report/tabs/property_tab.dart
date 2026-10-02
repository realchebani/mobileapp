import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/report/widgets/report_blocks.dart';
import 'package:mobileapp/seller_space/widgets/seller_space_format.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// V9b · "Le bien": the expert's description, the technical sheet with
/// the provenance of each line, and the rooms by level (from the dossier).
///
/// "À proximité, à pied" (points of interest) is hidden in v1.
class PropertyTab extends StatelessWidget {
  const new({
    required this.valuation,
    required this.property,
    required this.rooms,
    super.key,
  });

  final Valuation valuation;
  final Property property;
  final List<Room> rooms;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final description = valuation.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 14,
      children: [
        if (description != null) ReportParagraph(description),
        if (valuation.technicalSheet.isNotEmpty)
          ReportCard(
            title: l10n.reportTechnicalTitle,
            subtitle: l10n.reportTechnicalSubtitle,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final provenance in ValuationProvenance.values)
                    _Provenance(provenance),
                ],
              ),
              Column(
                children: [
                  for (final item in valuation.technicalSheet)
                    _TechnicalRow(item: item),
                ],
              ),
            ],
          ),
        if (rooms.isNotEmpty) _Surfaces(property: property, rooms: rooms),
      ],
    );
  }
}

class _Provenance extends StatelessWidget {
  const new(this.provenance);

  final ValuationProvenance provenance;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (provenance) {
      ValuationProvenance.declared => ProvenanceTag(
        ProvenanceKind.declared,
        label: l10n.reportProvenanceDeclared,
      ),
      ValuationProvenance.document => ProvenanceTag(
        ProvenanceKind.document,
        label: l10n.reportProvenanceDocument,
      ),
      ValuationProvenance.external => ProvenanceTag(
        ProvenanceKind.externalSource,
        label: l10n.reportProvenanceExternal,
      ),
      ValuationProvenance.verified => ProvenanceTag(
        ProvenanceKind.expertVerified,
        label: l10n.reportProvenanceVerified,
      ),
    };
  }
}

class _TechnicalRow extends StatelessWidget {
  const new({required this.item});

  final ValuationTechnicalItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.bordureCarte)),
        ),
        child: Row(
          spacing: RealestySpacing.xs,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                item.label,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            ),
            Expanded(
              child: Text(
                item.value,
                style: RealestyTextStyles.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: c.encre,
                ),
              ),
            ),
            _Provenance(item.provenance),
          ],
        ),
      ),
    );
  }
}

class _Surfaces extends StatelessWidget {
  const new({required this.property, required this.rooms});

  final Property property;
  final List<Room> rooms;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final living = rooms.where((room) => !room.isAnnex).toList();
    final annexes = rooms.where((room) => room.isAnnex).toList();
    final groups = <(String, List<Room>)>[
      for (final level in [...RoomLevel.values, null])
        if (living.where((room) => room.level == level).toList()
            case final levelRooms when levelRooms.isNotEmpty)
          (_levelLabel(l10n, level), levelRooms),
      if (annexes.isNotEmpty) (l10n.reportAnnexes, annexes),
    ];
    final total =
        property.livingAreaM2 ??
        living.fold<double>(0, (sum, room) => sum + room.areaM2);
    return ReportCard(
      title: l10n.reportSurfacesTitle,
      subtitle: property.measurementMethod == MeasurementMethod.scan
          ? l10n.reportSurfacesScan
          : l10n.reportSurfacesManual,
      children: [
        for (final (label, groupRooms) in groups)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.xs,
            children: [
              Text(
                label.toUpperCase(),
                style: RealestyTextStyles.caption.copyWith(
                  color: c.texteDiscret,
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = (constraints.maxWidth - 6) / 2;
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final room in groupRooms)
                        SizedBox(
                          width: width,
                          child: _RoomChip(room: room),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        KeyValueRow(
          label: l10n.reportSurfacesTotal,
          value: squareMeters(l10n, total),
          emphasized: true,
          divider: false,
        ),
      ],
    );
  }

  static String _levelLabel(AppLocalizations l10n, RoomLevel? level) =>
      switch (level) {
        RoomLevel.basement => l10n.surfacesLevelBasement,
        RoomLevel.groundFloor => l10n.surfacesLevelGroundFloor,
        RoomLevel.firstFloor => l10n.surfacesLevelFirstFloor,
        RoomLevel.secondFloor => l10n.surfacesLevelSecondFloor,
        RoomLevel.attic => l10n.surfacesLevelAttic,
        null => l10n.surfacesLevelNone,
      };
}

class _RoomChip extends StatelessWidget {
  const new({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final style = RealestyTextStyles.listSubtitle.copyWith(color: c.encre2);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(RealestyRadius.segment),
        ),
        child: Row(
          spacing: 6,
          children: [
            Expanded(
              child: Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            Text(
              squareMeters(context.l10n, room.areaM2),
              style: style.copyWith(
                fontWeight: FontWeight.w700,
                color: c.encre,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
