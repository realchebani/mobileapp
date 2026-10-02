import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/photos/cubit/room_photos_cubit.dart';
import 'package:mobileapp/seller_tunnel/photos/data/photo_capture.dart';
import 'package:mobileapp/seller_tunnel/photos/models/room_photo_suggestions.dart';
import 'package:mobileapp/seller_tunnel/photos/photo_services.dart';
import 'package:mobileapp/seller_tunnel/photos/view/photo_capture_page.dart';
import 'package:mobileapp/seller_tunnel/photos/view/photo_consent_page.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_cards.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_detail_sheet.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_input.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// What the photos screen hands back when it closes.
final class RoomPhotosResult extends Equatable {
  const new({required this.photosCount, this.room});

  /// Photos of the room now stored.
  final int photosCount;

  /// The answers of the room with the suggestions the seller applied, or
  /// null when none was applied (saved with the room, on V5c's
  /// "Continuer").
  final RoomInput? room;

  @override
  List<Object?> get props => [photosCount, room];
}

/// Opens the photos of the room [roomId] (full screen). [room] holds its
/// current answers (compared with the suggestions of the vision AI),
/// [otherNames] the names of the other rooms (to number a bedroom).
///
/// Reusable outside the seller tunnel (listing V11a, EPIC-08): it only
/// needs the ids and the room answers.
Future<RoomPhotosResult?> showRoomPhotos(
  BuildContext context, {
  required String ownerId,
  required String propertyId,
  required String roomId,
  required RoomInput room,
  List<String> otherNames = const [],
  bool readOnly = false,
}) {
  return Navigator.of(context).push<RoomPhotosResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => RoomPhotosPage(
        ownerId: ownerId,
        propertyId: propertyId,
        roomId: roomId,
        room: room,
        otherNames: otherNames,
        readOnly: readOnly,
      ),
    ),
  );
}

/// EPIC-15 · Photos de la pièce: take or pick photos, see them with their
/// checks, put one first, delete; the suggestions of the vision AI (when
/// accepted) to apply to the room.
class RoomPhotosPage extends StatelessWidget {
  const new({
    required this.ownerId,
    required this.propertyId,
    required this.roomId,
    required this.room,
    this.otherNames = const [],
    this.readOnly = false,
    super.key,
  });

  final String ownerId;
  final String propertyId;
  final String roomId;
  final RoomInput room;
  final List<String> otherNames;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final services = PhotoServices.of(context);
    return BlocProvider(
      create: (context) {
        final cubit = RoomPhotosCubit(
          repository: context.read<PropertyRepository>(),
          processor: services.photoProcessor,
          ownerId: ownerId,
          propertyId: propertyId,
          roomId: roomId,
          analysisEnabled: !readOnly && services.analysisAccepted,
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: RoomPhotosView(
        room: room,
        otherNames: otherNames,
        readOnly: readOnly,
      ),
    );
  }
}

class RoomPhotosView extends StatefulWidget {
  const new({
    required this.room,
    this.otherNames = const [],
    this.readOnly = false,
    super.key,
  });

  final RoomInput room;
  final List<String> otherNames;
  final bool readOnly;

  @override
  State<RoomPhotosView> createState() => _RoomPhotosViewState();
}

class _RoomPhotosViewState extends State<RoomPhotosView> {
  /// The answers of the room with the suggestions applied.
  late RoomInput _room = widget.room;
  int _applied = 0;

  void _close() {
    final state = context.read<RoomPhotosCubit>().state;
    Navigator.of(context).pop(
      RoomPhotosResult(
        photosCount: state.photos.length,
        room: _applied > 0 ? _room : null,
      ),
    );
  }

  /// Asks the consent to the vision AI before the first photo (whatever
  /// the answer, the photo can then be taken).
  Future<void> _askConsentOnce() async {
    final services = PhotoServices.of(context);
    final cubit = context.read<RoomPhotosCubit>();
    if (services.preferences?.consent != PhotoAnalysisConsent.unknown) return;
    if (await ensurePhotoAnalysisConsent(context)) cubit.enableAnalysis();
  }

  Future<void> _takePhotos() async {
    await _askConsentOnce();
    if (!mounted) return;
    final services = PhotoServices.of(context);
    await showPhotoCapture(
      context,
      cubit: context.read<RoomPhotosCubit>(),
      camera: services.newCamera(),
      processor: services.photoProcessor,
      tilt: services.tiltStream,
    );
  }

  Future<void> _pickPhotos() async {
    await _askConsentOnce();
    if (!mounted) return;
    final cubit = context.read<RoomPhotosCubit>();
    final library = PhotoServices.of(context).photoLibrary;
    final l10n = context.l10n;
    try {
      final photos = await library.pick(
        limit: RoomPhotosCubit.maxPhotos - cubit.state.count,
      );
      cubit.addFromLibrary(photos);
    } on PhotoAccessDenied {
      if (mounted) {
        showRealestySnackBar(
          context,
          l10n.photosNoticeAccessDenied,
          isError: true,
        );
      }
    } on Object {
      if (mounted) {
        showRealestySnackBar(
          context,
          l10n.photosNoticePickFailed,
          isError: true,
        );
      }
    }
  }

  /// "Désactiver les suggestions de l’IA": the consent is withdrawn.
  Future<void> _disableAnalysis() async {
    final cubit = context.read<RoomPhotosCubit>();
    await PhotoServices.of(context).preferences?.setConsent(given: false);
    cubit.disableAnalysis();
  }

  Future<void> _enableAnalysis() async {
    final cubit = context.read<RoomPhotosCubit>();
    if (await ensurePhotoAnalysisConsent(context, ask: true)) {
      cubit.enableAnalysis();
    }
  }

  Future<void> _openDetail(RoomPhotosState state, RoomPhoto photo) async {
    final cubit = context.read<RoomPhotosCubit>();
    final action = await showPhotoDetailSheet(
      context,
      photo: photo,
      index: state.photos.indexOf(photo),
      count: state.photos.length,
      bytes: state.previews[photo.id],
      url: state.urls[photo.storagePath],
      readOnly: widget.readOnly,
    );
    switch (action) {
      case PhotoDetailAction.makeMain:
        await cubit.moveFirst(photo);
      case PhotoDetailAction.delete:
        await cubit.delete(photo);
      case null:
        break;
    }
  }

  void _apply(RoomInput room) => setState(() {
    _room = room;
    _applied++;
  });

  static String _noticeMessage(AppLocalizations l10n, RoomPhotosNotice n) =>
      switch (n) {
        RoomPhotosNotice.limitReached => l10n.photosNoticeLimit,
        RoomPhotosNotice.uploadFailed => l10n.photosNoticeUploadFailed,
        RoomPhotosNotice.unreadable => l10n.photosNoticeUnreadable,
        RoomPhotosNotice.accessDenied => l10n.photosNoticeAccessDenied,
        RoomPhotosNotice.pickFailed => l10n.photosNoticePickFailed,
        RoomPhotosNotice.deleteFailed => l10n.photosNoticeDeleteFailed,
        RoomPhotosNotice.reorderFailed => l10n.photosNoticeReorderFailed,
        RoomPhotosNotice.analysisQuota => l10n.photosNoticeQuota,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final cubit = context.read<RoomPhotosCubit>();
    final state = context.watch<RoomPhotosCubit>().state;
    final services = PhotoServices.of(context);
    final readOnly = widget.readOnly;
    final ready = state.status == RoomPhotosStatus.ready;
    final suggestions = RoomPhotoSuggestions.of(
      room: _room,
      photos: state.photos,
      currentKind: RoomPhotoSuggestions.kindOfName(_room.name, l10n),
    );
    // The photo buttons do not fit side by side with large text.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.15;
    final buttons = [
      RealestyButton(
        label: l10n.photosTakePhotos,
        leadingIcon: RealestyIcons.camera,
        onPressed: state.canAdd ? () => unawaited(_takePhotos()) : null,
      ),
      RealestyButton(
        label: l10n.photosLibrary,
        variant: RealestyButtonVariant.secondary,
        leadingIcon: RealestyIcons.upload,
        onPressed: state.canAdd ? () => unawaited(_pickPhotos()) : null,
      ),
    ];
    // Android back: as the back button, once nothing is being sent.
    return PopScope<RoomPhotosResult>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !state.isBusy) _close();
      },
      child: BlocListener<RoomPhotosCubit, RoomPhotosState>(
        listenWhen: (previous, current) =>
            previous.noticeCount != current.noticeCount,
        listener: (context, state) => showRealestySnackBar(
          context,
          _noticeMessage(l10n, state.notice!),
          isError: true,
        ),
        child: TunnelScaffold(
          spacing: 14,
          header: _PhotosHeader(
            title: l10n.photosTitle(_room.name),
            subtitle: l10n.photosCount(state.photos.length),
            onBack: state.isBusy ? null : _close,
          ),
          actionBar: AgentActionBar(
            hint: state.isSending ? l10n.photosSendingHint : null,
            label: l10n.photosDone,
            isLoading: state.isBusy,
            onPressed: _close,
          ),
          children: [
            AgentIntro(
              message: _room.isMain
                  ? l10n.photosIntroMain(_room.name)
                  : l10n.photosIntro(_room.name),
            ),
            if (!readOnly) ...[
              const PhotoTipsCard(),
              if (stacked)
                Column(spacing: RealestySpacing.xs, children: buttons)
              else
                Row(
                  spacing: RealestySpacing.xs,
                  children: [
                    for (final button in buttons) Expanded(child: button),
                  ],
                ),
            ],
            switch (state.status) {
              RoomPhotosStatus.loading => Padding(
                padding: const EdgeInsets.all(RealestySpacing.lg),
                child: Center(
                  child: CircularProgressIndicator(color: c.vertTexte),
                ),
              ),
              RoomPhotosStatus.failure => Column(
                spacing: RealestySpacing.xs,
                children: [
                  Text(
                    l10n.photosLoadError,
                    textAlign: TextAlign.center,
                    style: RealestyTextStyles.body.copyWith(color: c.erreur),
                  ),
                  RealestyButton(
                    label: l10n.photosRetry,
                    variant: RealestyButtonVariant.text,
                    onPressed: () => unawaited(cubit.load()),
                  ),
                ],
              ),
              RoomPhotosStatus.ready when state.count == 0 => Text(
                l10n.photosEmpty,
                textAlign: TextAlign.center,
                style: RealestyTextStyles.listSubtitle.copyWith(
                  color: c.texteDiscret,
                ),
              ),
              RoomPhotosStatus.ready => GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: RealestySpacing.xs,
                crossAxisSpacing: RealestySpacing.xs,
                children: [
                  for (final (index, photo) in state.photos.indexed)
                    PhotoTile(
                      key: ValueKey(photo.id),
                      photo: photo,
                      isMain: index == 0,
                      bytes: state.previews[photo.id],
                      url: state.urls[photo.storagePath],
                      analyzing: state.analyzing.contains(photo.id),
                      busy: state.busyIds.contains(photo.id),
                      onTap: state.busyIds.isEmpty
                          ? () => unawaited(_openDetail(state, photo))
                          : null,
                    ),
                  for (final pending in state.pending)
                    PendingPhotoTile(
                      key: ValueKey(pending.id),
                      preview: pending.preview,
                      failed: pending.failed,
                      onRetry: () => cubit.retry(pending.id),
                      onDiscard: () => cubit.discard(pending.id),
                    ),
                ],
              ),
            },
            if (ready && state.count > 0)
              Text(
                l10n.photosLimit(state.count, RoomPhotosCubit.maxPhotos),
                textAlign: TextAlign.end,
                style: RealestyTextStyles.caption.copyWith(
                  color: c.texteDiscret,
                ),
              ),
            if (!readOnly && ready && state.photos.isNotEmpty)
              if (state.analysisEnabled)
                PhotoSuggestionsCard(
                  suggestions: suggestions,
                  analyzing: state.analyzing.length,
                  failedCount: state.analysisFailed.length,
                  appliedCount: _applied,
                  onApplyKind: (kind) =>
                      _apply(_room.withKind(kind, l10n, widget.otherNames)),
                  onApplyCovering: (covering) =>
                      _apply(_room.withFloorCovering(covering)),
                  onApplyGlazing: (glazing) =>
                      _apply(_room.withGlazing(glazing)),
                  onAddNote: (note) => _apply(_room.withNote(note)),
                  onRetry: () =>
                      state.analysisFailed.forEach(cubit.retryAnalysis),
                )
              else if (services.analysisAvailable)
                RealestyButton(
                  label: l10n.photosEnableAnalysis,
                  variant: RealestyButtonVariant.text,
                  leadingIcon: RealestyIcons.spark,
                  onPressed: () => unawaited(_enableAnalysis()),
                ),
            if (!readOnly && state.analysisEnabled)
              RealestyButton(
                label: l10n.photosDisableAnalysis,
                variant: RealestyButtonVariant.text,
                onPressed: () => unawaited(_disableAnalysis()),
              ),
          ],
        ),
      ),
    );
  }
}

/// Header of the photos screen: back, title and photo count.
class _PhotosHeader extends StatelessWidget {
  const new({required this.title, required this.subtitle, this.onBack});

  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          10,
          RealestySpacing.gutter,
          RealestySpacing.xs,
        ),
        child: Row(
          spacing: RealestySpacing.xs,
          children: [
            RealestyIconButton(
              icon: RealestyIcons.chevronLeft,
              semanticLabel: l10n.photosBack,
              onPressed: onBack,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: RealestyTextStyles.listSubtitle.copyWith(
                      color: c.texteDiscret,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
