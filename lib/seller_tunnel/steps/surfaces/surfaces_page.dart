import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/cubit/surfaces_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/dictated_rooms_list.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/room_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/rooms_table.dart';
import 'package:mobileapp/seller_tunnel/view/seller_tunnel_navigation.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// V5c · Récapitulatif des surfaces: the rooms table (typed, or dictated to
/// the voice agent: EPIC-14), the living area (surface habitable) of the
/// rooms and the area of the annexes (garage, cellier…).
///
/// `?dictee=1` (V5 "Dicter mes pièces") opens the dictation on arrival.
class SurfacesPage extends StatelessWidget {
  const new({super.key});

  /// Query parameter of V5 "Dicter mes pièces".
  static const dictationQuery = 'dictee';

  /// Whether the route asks to open the dictation (`?dictee=1`).
  static bool dictationRequested(BuildContext context) {
    try {
      final uri = GoRouter.of(context).state.uri;
      return uri.queryParameters[dictationQuery] == '1';
    } on Object {
      // Outside a router (or a mocked one): no dictation request.
      return false;
    }
  }

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
      child: SurfacesView(startDictation: dictationRequested(context)),
    );
  }
}

class SurfacesView extends StatefulWidget {
  const new({this.startDictation = false, super.key});

  /// Opens the dictation once the screen is shown.
  final bool startDictation;

  @override
  State<SurfacesView> createState() => _SurfacesViewState();
}

class _SurfacesViewState extends State<SurfacesView> {
  static const SellerTunnelStep _step = SellerTunnelStep.surfaces;

  final GlobalKey _tableKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.startDictation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _voiceAvailable(context)) unawaited(_openDictation());
      });
    }
  }

  static bool _voiceAvailable(BuildContext context) =>
      VoiceServices.of(context).isAvailable &&
      context.read<SellerTunnelCubit>().state.profile.hasVoice(_step);

  /// The rooms dictation (Night sheet; the agent stays silent until the
  /// spoken summary of "Terminer").
  Future<void> _openDictation() async {
    final l10n = context.l10n;
    final cubit = context.read<SurfacesCubit>();
    final propertyId = context.read<SellerTunnelCubit>().state.property!.id;
    final repository = VoiceServices.of(context).agentRepository!;
    await showStepVoiceSheet(
      context,
      propertyId: propertyId,
      step: AgentStep.rooms,
      form: cubit,
      title: l10n.surfacesVoiceTitle,
      intro: l10n.surfacesVoiceIntro,
      dictation: VoiceDefaults.silentRoomsDictation,
      summary: () => repository.roomsSummary(
        propertyId: propertyId,
        rooms: cubit.voiceContext.rooms,
      ),
      extra: BlocProvider.value(value: cubit, child: const DictatedRoomsList()),
    );
  }

  void _onSubmission(BuildContext context, SurfacesState state) {
    switch (state.submission) {
      case SurfacesSubmission.success:
        final tunnel = context.read<SellerTunnelCubit>()
          ..updateChildren(rooms: state.savedRooms);
        final property = tunnel.state.property!;
        unawaited(
          tunnel.saveAndContinue(_step, {
            PropertyColumns.livingAreaM2: state.livingArea,
            PropertyColumns.annexAreaM2: state.annexArea,
            PropertyColumns.provenance: property.mergeProvenance({
              PropertyColumns.livingAreaM2: Provenance.declared,
              PropertyColumns.annexAreaM2: Provenance.declared,
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
          onMicPressed: busy || !_voiceAvailable(context)
              ? null
              : () => unawaited(_openDictation()),
        ),
        children: [
          AgentIntro(
            message: count == 0
                ? l10n.surfacesAgentEmptyMessage
                : l10n.surfacesAgentMessage(
                    RoomArea.short(state.livingArea),
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
                livingArea: state.livingArea,
                annexArea: state.hasAnnexes ? state.annexArea : null,
                dictated: state.dictated,
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
