import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_labels.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_tile.dart';
import 'package:mobileapp/seller_tunnel/widgets/widgets.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// What the seller chose in the detail of a photo.
enum PhotoDetailAction { makeMain, delete }

/// Opens the detail of [photo] (not designed: a bottom sheet): the photo,
/// its checks and what the vision AI saw; "Mettre en premier" and
/// "Supprimer la photo" unless [readOnly].
Future<PhotoDetailAction?> showPhotoDetailSheet(
  BuildContext context, {
  required RoomPhoto photo,
  required int index,
  required int count,
  Uint8List? bytes,
  String? url,
  bool readOnly = false,
}) {
  return showModalBottomSheet<PhotoDetailAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => PhotoDetailSheet(
      photo: photo,
      index: index,
      count: count,
      bytes: bytes,
      url: url,
      readOnly: readOnly,
    ),
  );
}

/// Content of [showPhotoDetailSheet].
class PhotoDetailSheet extends StatelessWidget {
  const new({
    required this.photo,
    required this.index,
    required this.count,
    this.bytes,
    this.url,
    this.readOnly = false,
    super.key,
  });

  final RoomPhoto photo;

  /// Position of the photo (0 = the main one).
  final int index;
  final int count;
  final Uint8List? bytes;
  final String? url;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final issues = photoIssues(photo);
    final analysis = photo.analysis;
    final notes = [
      if (analysis?.peopleVisible ?? false) l10n.photosPeopleRetake,
      ...?analysis?.conditionNotes,
      if (analysis != null && analysis.personalItems.isNotEmpty)
        l10n.photosPersonalItems(analysis.personalItems.join(', ')),
    ];
    final text = RealestyTextStyles.listSubtitle.copyWith(
      height: 1.45,
      color: c.encre,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RealestySpacing.gutter,
          RealestySpacing.md,
          RealestySpacing.gutter,
          RealestySpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: RealestySpacing.sm,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.photosDetailTitle(index + 1, count),
                      style: RealestyTextStyles.title2.copyWith(color: c.encre),
                    ),
                  ),
                ),
                RealestyIconButton(
                  icon: RealestyIcons.close,
                  semanticLabel: l10n.photosDetailClose,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            AspectRatio(
              aspectRatio: (photo.width ?? 4) / (photo.height ?? 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RealestyRadius.card),
                child: PhotoImage(bytes: bytes, url: url, fit: BoxFit.contain),
              ),
            ),
            SectionLabel(l10n.photosDetailChecks),
            Text(
              issues.isEmpty
                  ? l10n.photosDetailNoIssue
                  : l10n.photosDetailIssues(photoIssuesLabel(l10n, issues)),
              style: text,
            ),
            if (notes.isNotEmpty) ...[
              SectionLabel(l10n.photosDetailAiNotes),
              for (final note in notes) Text('• $note', style: text),
            ],
            if (!readOnly) ...[
              const SizedBox(height: RealestySpacing.xxs),
              if (index > 0)
                RealestyButton(
                  label: l10n.photosDetailMakeMain,
                  variant: RealestyButtonVariant.secondary,
                  onPressed: () =>
                      Navigator.of(context).pop(PhotoDetailAction.makeMain),
                ),
              RealestyButton(
                label: l10n.photosDetailDelete,
                variant: RealestyButtonVariant.text,
                leadingIcon: RealestyIcons.trash,
                onPressed: () =>
                    Navigator.of(context).pop(PhotoDetailAction.delete),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
