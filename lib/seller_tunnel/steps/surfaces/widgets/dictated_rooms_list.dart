import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/cubit/surfaces_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// "Séjour · RDC · 38 m² · Parquet chêne · Double vitrage".
String roomSummaryLine(Room room, AppLocalizations l10n) => [
  room.name,
  ?room.level?.label(l10n),
  l10n.surfacesAreaValue(RoomArea.format(room.areaM2)),
  ?FloorCovering.labelOf(room.floorCovering, l10n),
  ?room.glazing?.label(l10n),
].join(' · ');

/// The rooms dictated during the V5c dictation (Night sheet, plan §3.2):
/// one line per room created or changed, its description below, and the
/// running total.
class DictatedRoomsList extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final state = context.watch<SurfacesCubit>().state;
    final rooms = state.dictatedRooms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: RealestySpacing.xs,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.surfacesVoiceDictatedTitle.toUpperCase(),
            style: RealestyTextStyles.caption.copyWith(
              color: c.nuitTexteDiscret,
            ),
          ),
        ),
        for (final room in rooms)
          Container(
            key: ValueKey(room.id),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.nuit2,
              borderRadius: BorderRadius.circular(RealestyRadius.field),
              border: Border.all(color: c.nuitBordure),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  roomSummaryLine(room, l10n),
                  style: RealestyTextStyles.bodySmall.copyWith(
                    color: c.nuitTexte,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (room.description case final description?)
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RealestyTextStyles.bodySmall.copyWith(
                      color: c.nuitTexteDiscret,
                    ),
                  ),
              ],
            ),
          ),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.surfacesVoiceTotal(
              RoomArea.short(state.livingArea),
              state.rooms.length,
            ),
            style: RealestyTextStyles.bodySmall.copyWith(color: c.lueur),
          ),
        ),
      ],
    );
  }
}
