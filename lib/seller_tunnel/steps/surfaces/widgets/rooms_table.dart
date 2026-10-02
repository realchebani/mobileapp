import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/seller_tunnel/voice/widgets/step_voice_sheet.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// The V5c rooms card: rooms grouped by level (name, surface, floor
/// covering, photos and edit buttons; annexes, rooms read on a plan and
/// main rooms still without a photo tagged) and the total bar (living
/// area, then the annexes).
class RoomsTable extends StatelessWidget {
  const new({
    required this.groups,
    required this.livingArea,
    required this.onEdit,
    this.onPhotos,
    this.requirePhotos = false,
    this.annexArea,
    this.dictated = const {},
    this.toConfirm = const {},
    super.key,
  });

  /// Opens the photos of a room (EPIC-15); null disables the buttons.
  final ValueChanged<Room>? onPhotos;

  /// Whether a main room needs a photo (types with rooms, EPIC-15).
  final bool requirePhotos;

  /// Rooms by level (null: no level), as `SurfacesState.roomsByLevel`.
  final List<(RoomLevel?, List<Room>)> groups;

  /// Surface habitable: the rooms that are not annexes.
  final double livingArea;

  /// Area of the annexes; null hides the annexes line.
  final double? annexArea;

  /// Edits a room; null disables the edit buttons.
  final ValueChanged<Room>? onEdit;

  /// Ids of the rooms dictated on this visit ("Dicté").
  final Set<String> dictated;

  /// Ids of the rooms said on another step, not confirmed yet (EPIC-16,
  /// « À confirmer »).
  final Set<String> toConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final border = BorderSide(color: c.bordureCarte);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(RealestyRadius.card),
        border: Border.fromBorderSide(border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(RealestySpacing.md),
              child: Text(
                l10n.surfacesEmpty,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            ),
          for (final (level, rooms) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Semantics(
                header: true,
                child: Text(
                  (level?.label(l10n) ?? l10n.surfacesLevelNone).toUpperCase(),
                  style: RealestyTextStyles.caption.copyWith(
                    color: c.texteDiscret,
                  ),
                ),
              ),
            ),
            for (final room in rooms)
              _RoomRow(
                key: ValueKey(room.id),
                room: room,
                border: border,
                dictated: dictated.contains(room.id),
                toConfirm: toConfirm.contains(room.id),
                photoRequired:
                    requirePhotos && room.isMain && room.photosCount == 0,
                onEdit: onEdit == null ? null : () => onEdit!(room),
                onPhotos: onPhotos == null ? null : () => onPhotos!(room),
              ),
          ],
          ColoredBox(
            color: c.encre,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: RealestySpacing.xxs,
                children: [
                  Row(
                    spacing: RealestySpacing.xs,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.surfacesTotalLabel,
                          style: RealestyTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.surface,
                          ),
                        ),
                      ),
                      Text(
                        l10n.surfacesAreaValue(RoomArea.format(livingArea)),
                        style: RealestyTextStyles.title2.copyWith(
                          fontSize: 20,
                          height: 1.1,
                          letterSpacing: -0.4,
                          color: c.surface,
                        ),
                      ),
                    ],
                  ),
                  if (annexArea case final annexArea?)
                    Text(
                      l10n.surfacesAnnexTotal(RoomArea.format(annexArea)),
                      textAlign: TextAlign.end,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.nuitTexteDiscret,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomRow extends StatelessWidget {
  const new({
    required this.room,
    required this.border,
    required this.onEdit,
    this.onPhotos,
    this.dictated = false,
    this.toConfirm = false,
    this.photoRequired = false,
    super.key,
  });

  final Room room;
  final BorderSide border;
  final VoidCallback? onEdit;
  final VoidCallback? onPhotos;
  final bool dictated;
  final bool toConfirm;

  /// A main room without a photo (needed to send the dossier).
  final bool photoRequired;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final textStyle = RealestyTextStyles.listTitle.copyWith(color: c.encre);
    final fromPlan = room.source == RoomSource.plan;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 14, right: 2),
      decoration: BoxDecoration(border: Border(top: border)),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            flex: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  if (room.isAnnex || dictated || toConfirm || fromPlan)
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(room.name, style: textStyle),
                        if (room.isAnnex)
                          RealestyBadge(label: l10n.surfacesAnnexTag),
                        if (toConfirm)
                          const ToConfirmTag()
                        else if (dictated)
                          const DictatedTag(),
                        if (fromPlan)
                          ProvenanceTag(
                            ProvenanceKind.document,
                            label: l10n.surfacesPlanTag,
                          ),
                      ],
                    )
                  else
                    Text(room.name, style: textStyle),
                  if (photoRequired)
                    Text(
                      l10n.surfacesPhotoRequired,
                      style: RealestyTextStyles.caption.copyWith(
                        color: c.attention,
                      ),
                    ),
                  if (room.description case final description?)
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RealestyTextStyles.listSubtitle.copyWith(
                        color: c.texteDiscret,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                RoomArea.format(room.areaM2),
                softWrap: false,
                style: textStyle.copyWith(fontFamily: RealestyFonts.sora),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              FloorCovering.labelOf(room.floorCovering, l10n) ?? '',
              style: RealestyTextStyles.listSubtitle.copyWith(
                color: c.texteDiscret,
              ),
            ),
          ),
          RealestyPressable(
            semanticLabel: l10n.surfacesRoomPhotos(room.name, room.photosCount),
            onPressed: onPhotos,
            child: SizedBox(
              width: 40,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RealestyIcon(
                    RealestyIcons.camera,
                    size: 18,
                    color: photoRequired ? c.attention : c.texteDiscret,
                  ),
                  if (room.photosCount > 0)
                    Positioned(
                      right: 2,
                      top: 8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.vertTexte,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${room.photosCount}',
                          style: RealestyTextStyles.caption.copyWith(
                            fontSize: 10,
                            height: 1,
                            color: c.surface,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          RealestyPressable(
            semanticLabel: l10n.surfacesEditRoom(room.name),
            onPressed: onEdit,
            child: SizedBox(
              width: 40,
              height: 48,
              child: Center(
                child: RealestyIcon(
                  RealestyIcons.pen,
                  size: 16,
                  color: c.texteDiscret,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
