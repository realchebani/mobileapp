import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:mobileapp/seller_tunnel/photos/view/room_photos_page.dart';
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

/// V5c · Récapitulatif des surfaces: the rooms table (typed, dictated to
/// the voice agent: EPIC-14, or read on a plan: EPIC-15), the living area
/// (surface habitable) of the rooms and the area of the annexes (garage,
/// cellier…), and the photos of each room (EPIC-15: a main room needs one
/// to send the dossier).
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
    final tunnel = context.read<SellerTunnelCubit>().state;
    // EPIC-16: rooms said on another step join the table « À confirmer ».
    final trace = StepVoiceFirst.createTrace(tunnel, SellerTunnelStep.surfaces);
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: trace),
        BlocProvider(
          create: (context) => SurfacesCubit(
            propertyRepository: context.read<PropertyRepository>(),
            propertyId: tunnel.property!.id,
            rooms: tunnel.rooms,
            pendingRooms: trace.state.prefilledOf(PendingKind.room),
          ),
        ),
      ],
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
    } else {
      // EPIC-16: no room yet, the dictation opens by itself (voice mode).
      StepVoiceFirst.schedule(
        context,
        _step,
        () => _openDictation(autoOpened: true),
        when: context.read<SurfacesCubit>().state.rooms.isEmpty,
      );
    }
  }

  static bool _voiceAvailable(BuildContext context) =>
      VoiceServices.of(context).isAvailable &&
      context.read<SellerTunnelCubit>().state.profile.hasVoice(_step);

  /// The rooms dictation (Night sheet; the agent stays silent until the
  /// spoken summary of "Terminer").
  Future<void> _openDictation({bool autoOpened = false}) async {
    final l10n = context.l10n;
    final cubit = context.read<SurfacesCubit>();
    final propertyId = context.read<SellerTunnelCubit>().state.property!.id;
    final repository = VoiceServices.of(context).agentRepository!;
    await StepVoiceFirst.openSheet(
      context,
      autoOpened: autoOpened,
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
        // Totals of rooms all read on a plan come from a document.
        Provenance provenanceOf(Iterable<Room> rooms) =>
            rooms.isNotEmpty &&
                rooms.every((room) => room.source == RoomSource.plan)
            ? Provenance.document
            : Provenance.declared;
        final living = provenanceOf(state.rooms.where((room) => !room.isAnnex));
        final annex = provenanceOf(state.rooms.where((room) => room.isAnnex));
        // EPIC-16: the totals are computed from the rooms (read on a plan:
        // extracted), with the notes of the step.
        final traced = StepVoiceFirst.save(
          context,
          {
            PropertyColumns.livingAreaM2: state.livingArea,
            PropertyColumns.annexAreaM2: state.annexArea,
            PropertyColumns.provenance: property.mergeProvenance({
              PropertyColumns.livingAreaM2: living,
              PropertyColumns.annexAreaM2: annex,
            }),
          },
          voiceSource: (column, value, at) => null,
          kinds: {
            if (living == Provenance.document)
              PropertyColumns.livingAreaM2: FieldSourceKind.extracted,
            if (annex == Provenance.document)
              PropertyColumns.annexAreaM2: FieldSourceKind.extracted,
          },
        );
        unawaited(
          tunnel.saveStepAndContinue(
            _step,
            traced.patch,
            resolve: {
              for (final resolution in {
                ...traced.resolutions.keys,
                ...state.pendingResolutions.keys,
              })
                resolution: [
                  ...?traced.resolutions[resolution],
                  ...?state.pendingResolutions[resolution],
                ],
            },
          ),
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
      photosCount: 0,
    );
    if (!mounted) return;
    switch (result) {
      case RoomSheetSaved(:final room):
        cubit.roomAdded(room);
      case RoomSheetPhotos(:final room):
        cubit.roomAdded(room);
        await _openPhotos(cubit.state.rooms.last);
      case RoomSheetDeleted() || null:
        break;
    }
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
      photosCount: room.photosCount,
    );
    if (!mounted) return;
    switch (result) {
      case RoomSheetSaved(:final room):
        cubit.roomEdited(id, room);
      case RoomSheetPhotos(:final room):
        cubit.roomEdited(id, room);
        await _openPhotos(
          cubit.state.rooms.firstWhere((room) => room.id == id),
        );
      case RoomSheetDeleted():
        cubit.roomDeleted(id);
      case null:
        break;
    }
  }

  /// The photos of [room] (EPIC-15): the room is written first (a photo
  /// needs its row) and recorded in the dossier at once; the suggestions
  /// the seller applied come back to the room form.
  Future<void> _openPhotos(Room room) async {
    final cubit = context.read<SurfacesCubit>();
    final tunnel = context.read<SellerTunnelCubit>();
    final l10n = context.l10n;
    final id = room.id!;
    await cubit.preparePhotos(id);
    final saved = cubit.state.photosRoom;
    if (!mounted) return;
    if (saved == null || saved.id != id) {
      showRealestySnackBar(context, l10n.surfacesRoomSaveError, isError: true);
      return;
    }
    _recordInTunnel(tunnel, saved);
    final result = await showRoomPhotos(
      context,
      ownerId: tunnel.state.property!.ownerId,
      propertyId: saved.propertyId,
      roomId: id,
      room: RoomInput.fromRoom(saved),
      otherNames: [
        for (final other in cubit.state.rooms)
          if (other.id != id) other.name,
      ],
    );
    if (result == null || !mounted) return;
    cubit.photosChanged(id, result.photosCount);
    _recordInTunnel(
      tunnel,
      cubit.state.rooms.firstWhere((room) => room.id == id),
      savedRow: saved,
    );
    if (result.room case final edited?) cubit.roomEdited(id, edited);
  }

  /// Records the stored row of a room in the dossier, with its photo
  /// count (from [room]).
  static void _recordInTunnel(
    SellerTunnelCubit tunnel,
    Room room, {
    Room? savedRow,
  }) {
    final row = savedRow == null
        ? room
        : Room.fromJson({
            ...savedRow.toJson(),
            'photos_count': room.photosCount,
          });
    final rooms = tunnel.state.rooms;
    tunnel.updateChildren(
      rooms: rooms.any((other) => other.id == row.id)
          ? [
              for (final other in rooms)
                if (other.id == row.id) row else other,
            ]
          : [...rooms, row],
    );
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
    final requirePhotos = context.select<SellerTunnelCubit, bool>(
      (cubit) => cubit.state.profile.requiresRoomPhotos,
    );
    final mainRooms = state.mainRooms.length;
    final missingPhotos = requirePhotos
        ? state.mainRoomsWithoutPhotos.length
        : 0;
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
          onPressed: () => unawaited(
            cubit.submit(
              confirmed: context.read<StepTraceCubit>().state.confirmed,
            ),
          ),
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
                RealestyBadge(
                  label: l10n.surfacesPhotosBadge(state.photosCount),
                ),
                // Rooms read on a plan (EPIC-15): tagged "Plan" below.
                if (state.rooms.any((room) => room.source == RoomSource.plan))
                  const ProvenanceTag(ProvenanceKind.document),
                if (requirePhotos && mainRooms > 0)
                  RealestyBadge(
                    label: l10n.surfacesMainPhotosBadge(
                      mainRooms - missingPhotos,
                      mainRooms,
                    ),
                    variant: missingPhotos == 0
                        ? RealestyBadgeVariant.certified
                        : RealestyBadgeVariant.toComplete,
                    showIcon: missingPhotos == 0,
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
                toConfirm: {
                  for (final MapEntry(key: room, value: pending)
                      in state.toConfirm.entries)
                    if (!context
                        .watch<StepTraceCubit>()
                        .state
                        .confirmed
                        .contains(pending))
                      room,
                },
                requirePhotos: requirePhotos,
                onEdit: busy ? null : (room) => _editRoom(state, room),
                onPhotos: busy ? null : (room) => unawaited(_openPhotos(room)),
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
          if (missingPhotos > 0)
            InlineBanner(
              message: l10n.surfacesPhotosMissingHint,
              icon: RealestyIcons.camera,
            ),
          RealestyButton(
            label: l10n.surfacesAddRoom,
            variant: RealestyButtonVariant.text,
            leadingIcon: RealestyIcons.plus,
            height: RealestySpacing.minTouchTarget,
            onPressed: busy ? null : () => _addRoom(state),
          ),
          StepNotesField(enabled: !busy),
        ],
      ),
    );
  }
}
