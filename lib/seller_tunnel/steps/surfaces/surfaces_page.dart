import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/cubit/surfaces_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/room_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/rooms_table.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V5c · Récapitulatif des surfaces: the rooms table (manual entry in v1)
/// and the living area it adds up to.
class SurfacesPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tunnel = context.read<SellerTunnelCubit>().state;
        return SurfacesCubit(
          propertyRepository: context.read<PropertyRepository>(),
          propertyId: tunnel.property!.id,
          rooms: tunnel.rooms,
        );
      },
      child: const SurfacesView(),
    );
  }
}

class SurfacesView extends StatefulWidget {
  const new({super.key});

  @override
  State<SurfacesView> createState() => _SurfacesViewState();
}

class _SurfacesViewState extends State<SurfacesView> {
  static const SellerTunnelStep _step = SellerTunnelStep.surfaces;

  final GlobalKey _tableKey = GlobalKey();

  void _onSubmission(BuildContext context, SurfacesState state) {
    switch (state.submission) {
      case SurfacesSubmission.success:
        final tunnel = context.read<SellerTunnelCubit>()
          ..updateChildren(rooms: state.savedRooms);
        final property = tunnel.state.property!;
        unawaited(
          tunnel.saveAndContinue(_step, {
            PropertyColumns.livingAreaM2: state.totalArea,
            PropertyColumns.provenance: property.mergeProvenance({
              PropertyColumns.livingAreaM2: Provenance.declared,
            }),
          }),
        );
      case SurfacesSubmission.failure:
        context.read<SellerTunnelCubit>().updateChildren(
          rooms: state.savedRooms,
        );
        showRealestySnackBar(
          context,
          context.l10n.sellerTunnelSaveError,
          isError: true,
        );
      case SurfacesSubmission.idle:
      case SurfacesSubmission.inProgress:
        break;
    }
  }

  void _revealError() {
    final target = _tableKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: RealestyMotion.page,
        alignment: 0.1,
      );
    }
  }

  Future<void> _addRoom(SurfacesState state) async {
    final cubit = context.read<SurfacesCubit>();
    final result = await showRoomSheet(
      context,
      defaultLevel: state.rooms.lastOrNull?.level ?? RoomLevel.groundFloor,
      otherNames: [for (final room in state.rooms) room.name],
    );
    if (!mounted) return;
    if (result is RoomSheetSaved) cubit.roomAdded(result.room);
  }

  Future<void> _editRoom(SurfacesState state, Room room) async {
    final cubit = context.read<SurfacesCubit>();
    final id = room.id!;
    final result = await showRoomSheet(
      context,
      initial: RoomInput.fromRoom(room),
      otherNames: [
        for (final other in state.rooms)
          if (other.id != id) other.name,
      ],
    );
    if (!mounted) return;
    switch (result) {
      case RoomSheetSaved(:final room):
        cubit.roomEdited(id, room);
      case RoomSheetDeleted():
        cubit.roomDeleted(id);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<SurfacesCubit>();
    final state = context.watch<SurfacesCubit>().state;
    final tunnelSaving = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.isSaving,
    );
    final busy = tunnelSaving || state.isSubmitting;
    final count = state.rooms.length;
    return MultiBlocListener(
      listeners: [
        BlocListener<SurfacesCubit, SurfacesState>(
          listenWhen: (previous, current) =>
              previous.submission != current.submission,
          listener: _onSubmission,
        ),
        BlocListener<SurfacesCubit, SurfacesState>(
          listenWhen: (previous, current) =>
              previous.submitAttempts != current.submitAttempts,
          listener: (context, state) => _revealError(),
        ),
      ],
      child: TunnelScaffold(
        spacing: 14,
        header: TunnelHeader(
          step: _step,
          onBack: busy ? null : () => context.goBackFrom(_step),
        ),
        actionBar: AgentActionBar(
          hint: l10n.tunnelHintVoiceOrScreen,
          label: l10n.surfacesContinue,
          isLoading: busy,
          onPressed: cubit.submit,
        ),
        children: [
          AgentIntro(
            message: count == 0
                ? l10n.surfacesAgentEmptyMessage
                : l10n.surfacesAgentMessage(
                    RoomArea.short(state.totalArea),
                    state.mainRoomsCount,
                  ),
          ),
          if (count > 0)
            Wrap(
              spacing: RealestySpacing.xs,
              runSpacing: RealestySpacing.xs,
              children: [
                RealestyBadge(
                  label: l10n.surfacesRoomsCountBadge(count),
                  variant: RealestyBadgeVariant.certified,
                ),
              ],
            ),
          Column(
            key: _tableKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.xs,
            children: [
              RoomsTable(
                groups: state.roomsByLevel,
                totalArea: state.totalArea,
                onEdit: busy ? null : (room) => _editRoom(state, room),
              ),
              if (state.showErrors && !state.isValid)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.surfacesErrorNoRooms,
                    style: RealestyTextStyles.fieldError.copyWith(
                      color: c.erreur,
                    ),
                  ),
                ),
            ],
          ),
          RealestyButton(
            label: l10n.surfacesAddRoom,
            variant: RealestyButtonVariant.text,
            leadingIcon: RealestyIcons.plus,
            height: RealestySpacing.minTouchTarget,
            onPressed: busy ? null : () => _addRoom(state),
          ),
        ],
      ),
    );
  }
}
