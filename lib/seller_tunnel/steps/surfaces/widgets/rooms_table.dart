import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// The V5c rooms card: rooms grouped by level (name, surface, floor
/// covering, edit button; annexes tagged) and the total bar (living area,
/// then the annexes).
class RoomsTable extends StatelessWidget {
  const new({
    required this.groups,
    required this.livingArea,
    required this.onEdit,
    this.annexArea,
    super.key,
  });

  /// Rooms by level (null: no level), as `SurfacesState.roomsByLevel`.
  final List<(RoomLevel?, List<Room>)> groups;

  /// Surface habitable: the rooms that are not annexes.
  final double livingArea;

  /// Area of the annexes; null hides the annexes line.
  final double? annexArea;

  /// Edits a room; null disables the edit buttons.
  final ValueChanged<Room>? onEdit;

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
                onEdit: onEdit == null ? null : () => onEdit!(room),
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
    super.key,
  });

  final Room room;
  final BorderSide border;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final textStyle = RealestyTextStyles.listTitle.copyWith(color: c.encre);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.only(left: 14, right: 2),
      decoration: BoxDecoration(border: Border(top: border)),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            flex: 8,
            child: room.isAnnex
                ? Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(room.name, style: textStyle),
                      RealestyBadge(label: l10n.surfacesAnnexTag),
                    ],
                  )
                : Text(room.name, style: textStyle),
          ),
          SizedBox(
            width: 64,
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
            semanticLabel: l10n.surfacesEditRoom(room.name),
            onPressed: onEdit,
            child: SizedBox.square(
              dimension: 48,
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
