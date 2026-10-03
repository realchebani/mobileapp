import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:mobileapp/seller_space/sale/listing/photos/listing_photos_cubit.dart';
import 'package:mobileapp/seller_space/sale/widgets/photo_examples.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_scaffold.dart';
import 'package:mobileapp/seller_tunnel/photos/photo_services.dart';
import 'package:mobileapp/seller_tunnel/photos/view/photo_capture_page.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Photos of the listing (EPIC-08 · US-08.6, not in the design canvas):
/// every dossier photo is copied the first time; new photos with the photo
/// screen of EPIC-15 or from the library; tap a photo to make it the cover
/// or remove it; "minimum 5" to publish, 40 at most.
class ListingPhotosPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final saleCubit = context.read<SaleCubit>();
    final state = saleCubit.state;
    final services = PhotoServices.of(context);
    return BlocProvider(
      create: (context) {
        final cubit = ListingPhotosCubit(
          saleRepository: context.read<SaleRepository>(),
          propertyRepository: context.read<PropertyRepository>(),
          processor: services.photoProcessor,
          sale: state.sale!,
          ownerId: context.read<ProfileCubit>().state.profile?.id ?? '',
          members: state.members,
          onImported: () => unawaited(saleCubit.refresh()),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const ListingPhotosView(),
    );
  }
}

/// The view of [ListingPhotosPage].
class ListingPhotosView extends StatelessWidget {
  const new({super.key});

  Future<void> _takePhotos(BuildContext context) {
    final services = PhotoServices.of(context);
    return showPhotoCaptureFor(
      context,
      target: context.read<ListingPhotosCubit>(),
      camera: services.newCamera(),
      processor: services.photoProcessor,
      tilt: services.tiltStream,
    );
  }

  Future<void> _pickPhotos(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<ListingPhotosCubit>();
    final library = PhotoServices.of(context).photoLibrary;
    try {
      final raw = await library.pick(
        limit: ListingPhotosCubit.maxPhotos - cubit.state.count,
      );
      cubit.addFromLibrary(raw);
    } on Object {
      if (context.mounted) {
        showRealestySnackBar(
          context,
          l10n.listingPhotosPickFailed,
          isError: true,
        );
      }
    }
  }

  Future<void> _openPhoto(BuildContext context, ListingPhoto photo) async {
    final l10n = context.l10n;
    final cubit = context.read<ListingPhotosCubit>();
    final isCover = cubit.state.photos.firstOrNull?.id == photo.id;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.realestyColors.ivoire,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RealestySpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: RealestySpacing.xs,
            children: [
              if (!isCover)
                RealestyButton(
                  label: l10n.listingPhotosMakeCover,
                  leadingIcon: RealestyIcons.star,
                  onPressed: () => Navigator.of(sheetContext).pop('cover'),
                ),
              RealestyButton(
                label: l10n.listingPhotosRemove,
                variant: RealestyButtonVariant.secondary,
                leadingIcon: RealestyIcons.trash,
                onPressed: () => Navigator.of(sheetContext).pop('remove'),
              ),
            ],
          ),
        ),
      ),
    );
    switch (action) {
      case 'cover':
        await cubit.makeCover(photo);
      case 'remove':
        await cubit.remove(photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return BlocListener<ListingPhotosCubit, ListingPhotosState>(
      listenWhen: (previous, current) =>
          current.noticeCount != previous.noticeCount,
      listener: (context, state) =>
          showRealestySnackBar(context, switch (state.notice!) {
            ListingPhotosNotice.limitReached => l10n.saleErrorPhotoLimit,
            ListingPhotosNotice.addFailed => l10n.listingPhotosAddFailed,
            ListingPhotosNotice.changeFailed => l10n.listingPhotosChangeFailed,
          }, isError: true),
      child: BlocBuilder<ListingPhotosCubit, ListingPhotosState>(
        builder: (context, state) {
          final cubit = context.read<ListingPhotosCubit>();
          return SaleScaffold(
            title: l10n.listingPhotosTitle,
            badges: [
              RealestyBadge(
                label: l10n.listingPhotosCount(
                  state.photos.length,
                  ListingPhotosCubit.minPhotos,
                ),
                variant: state.photos.length >= ListingPhotosCubit.minPhotos
                    ? RealestyBadgeVariant.certified
                    : RealestyBadgeVariant.toComplete,
              ),
            ],
            children: [
              const PhotoExamples(),
              Text(
                l10n.listingPhotosIntro,
                style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
              ),
              if (state.status == ListingPhotosStatus.failure)
                InlineBanner(message: l10n.listingPhotosLoadError)
              else if (state.status == ListingPhotosStatus.loading)
                Center(child: CircularProgressIndicator(color: c.vertTexte))
              else ...[
                if (state.importing)
                  InlineBanner(
                    message: l10n.listingPhotosImporting,
                    variant: InlineBannerVariant.info,
                  ),
                if (state.photos.isEmpty && !state.importing)
                  InlineBanner(
                    message: l10n.listingPhotosEmpty,
                    variant: InlineBannerVariant.info,
                  ),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: RealestySpacing.xs,
                  crossAxisSpacing: RealestySpacing.xs,
                  children: [
                    for (final (index, photo) in state.photos.indexed)
                      _Tile(
                        photo: photo,
                        url: state.urls[photo.storagePath],
                        isCover: index == 0,
                        onTap: state.busy
                            ? null
                            : () => unawaited(_openPhoto(context, photo)),
                      ),
                    for (var i = 0; i < state.adding; i++)
                      ColoredBox(
                        color: c.imagePlaceholder,
                        child: Center(
                          child: CircularProgressIndicator(color: c.vertTexte),
                        ),
                      ),
                  ],
                ),
                RealestyButton(
                  label: l10n.listingPhotosTake,
                  leadingIcon: RealestyIcons.camera,
                  onPressed: state.canAdd
                      ? () => unawaited(_takePhotos(context))
                      : null,
                ),
                RealestyButton(
                  label: l10n.listingPhotosLibrary,
                  variant: RealestyButtonVariant.secondary,
                  leadingIcon: RealestyIcons.upload,
                  onPressed: state.canAdd
                      ? () => unawaited(_pickPhotos(context))
                      : null,
                ),
                RealestyButton(
                  label: l10n.listingPhotosReimport,
                  variant: RealestyButtonVariant.text,
                  onPressed: state.importing || !state.canAdd
                      ? null
                      : () => unawaited(cubit.importDossierPhotos()),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const new({
    required this.photo,
    required this.url,
    required this.isCover,
    required this.onTap,
  });

  final ListingPhoto photo;
  final String? url;
  final bool isCover;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final caption = photo.caption;
    return RealestyPressable(
      semanticLabel: caption ?? l10n.listingPhotosPhoto,
      onPressed: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RealestyRadius.field),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(url: url),
            if (isCover)
              Positioned(
                left: RealestySpacing.xxs,
                top: RealestySpacing.xxs,
                right: RealestySpacing.xxs,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RealestyBadge(
                    label: l10n.listingPhotosCover,
                    variant: RealestyBadgeVariant.premium,
                    showIcon: false,
                  ),
                ),
              ),
            if (caption != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: c.nuit.withValues(alpha: 0.55),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RealestySpacing.xxs,
                      vertical: 2,
                    ),
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RealestyTextStyles.caption.copyWith(
                        color: c.nuitTexte,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
