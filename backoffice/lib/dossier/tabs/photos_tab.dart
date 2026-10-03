import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/dossier/widgets/field_row.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

/// Room photos (EPIC-15) with the phone checks and the AI suggestions.
class PhotosTab extends StatelessWidget {
  const new({required this.dossier, super.key});

  final Dossier dossier;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final urls = context.select<DossierCubit, Map<String, String>>(
      (cubit) => cubit.state.photoUrls,
    );
    final cubit = context.read<DossierCubit>();
    if (dossier.photos.isEmpty && !dossier.rooms.any((r) => r.isMain)) {
      return BoMessage(title: l10n.photosNone);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${l10n.photosIntro} ${l10n.photosExpired}',
                style: RealestyTextStyles.bodySmall.copyWith(color: c.encre2),
              ),
            ),
            if (dossier.photos.isNotEmpty)
              RealestyButton(
                label: urls.isEmpty ? l10n.photosLoad : l10n.photosRefresh,
                expand: false,
                variant: RealestyButtonVariant.secondary,
                onPressed: () => runGuarded(context, () {
                  cubit.clearPhotoUrls();
                  return cubit.loadPhotos();
                }),
              ),
          ],
        ),
        const SizedBox(height: RealestySpacing.md),
        for (final room in dossier.rooms)
          if (dossier.photosOf(room.id) case final photos
              when photos.isNotEmpty || room.isMain) ...[
            BoCard(
              title: room.name,
              trailing: photos.isEmpty
                  ? WarningChip(l10n.photosMissingMain)
                  : null,
              child: Wrap(
                spacing: RealestySpacing.md,
                runSpacing: RealestySpacing.md,
                children: [
                  for (final photo in photos)
                    _PhotoTile(photo: photo, url: urls[photo.id]),
                ],
              ),
            ),
            const SizedBox(height: RealestySpacing.md),
          ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const new({required this.photo, required this.url});

  final DossierPhoto photo;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final analysis = photo.analysis;
    final small = RealestyTextStyles.bodySmall.copyWith(color: c.encre2);
    final summary = analysis == null
        ? null
        : [
            ?analysis['room_kind'] as String?,
            ?analysis['floor_covering'] as String?,
            ?analysis['glazing'] as String?,
            if (analysis['condition_notes'] case final List<dynamic> notes)
              ...notes.whereType<String>(),
          ].join(' · ');
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RealestyRadius.field),
              child: ColoredBox(
                color: c.imagePlaceholder,
                child: url == null
                    ? const Center(child: RealestyIcon(RealestyIcons.camera))
                    : InkWell(
                        onTap: () => context.read<Browser>().open(url!),
                        child: Image.network(
                          url!,
                          fit: BoxFit.cover,
                          semanticLabel: l10n.photosOpen,
                          errorBuilder: (_, _, _) => const Center(
                            child: RealestyIcon(RealestyIcons.warning),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: RealestySpacing.xxs),
          if (photo.issues.isNotEmpty)
            Text(l10n.photosIssues(photo.issues.join(', ')), style: small),
          if (summary != null && summary.isNotEmpty)
            Text(l10n.photosAi(summary), style: small),
          if (analysis?['people_visible'] == true)
            WarningChip(l10n.photosPerson),
        ],
      ),
    );
  }
}
