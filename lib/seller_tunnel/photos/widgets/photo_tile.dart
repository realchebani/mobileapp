import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/photos/widgets/photo_labels.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:property_repository/property_repository.dart';

/// The image of a photo: its local bytes, else its signed URL, else a
/// placeholder.
class PhotoImage extends StatelessWidget {
  const new({this.bytes, this.url, this.fit = BoxFit.cover, super.key});

  final Uint8List? bytes;
  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final c = context.realestyColors;
    final placeholder = ColoredBox(
      color: c.imagePlaceholder,
      child: Center(
        child: RealestyIcon(RealestyIcons.camera, color: c.texteDiscret),
      ),
    );
    if (bytes case final bytes?) {
      return Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    if (url case final url?) {
      return Image.network(
        url,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return placeholder;
  }
}

/// A stored photo of the room grid: its image, "Principale" on the first
/// one, its defects and "Personne visible" from the checks and the vision
/// AI, a spinner while analysed or changed.
class PhotoTile extends StatelessWidget {
  const new({
    required this.photo,
    required this.isMain,
    required this.onTap,
    this.bytes,
    this.url,
    this.analyzing = false,
    this.busy = false,
    super.key,
  });

  final RoomPhoto photo;
  final bool isMain;
  final Uint8List? bytes;
  final String? url;
  final bool analyzing;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    final issues = photoIssues(photo);
    final people = photo.analysis?.peopleVisible ?? false;
    return RealestyPressable(
      semanticLabel: [
        l10n.photosTile,
        if (isMain) l10n.photosMain,
        if (people) l10n.photosPeopleVisible,
        if (issues.isNotEmpty) photoIssuesLabel(l10n, issues),
      ].join(', '),
      onPressed: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RealestyRadius.field),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoImage(bytes: bytes, url: url),
            if (isMain)
              Positioned(
                left: 6,
                top: 6,
                child: _Pill(label: l10n.photosMain, color: c.nuit),
              ),
            if (analyzing || busy)
              Positioned(
                right: 6,
                top: 6,
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.surface,
                  ),
                ),
              ),
            if (people || issues.isNotEmpty)
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (people)
                      _Pill(label: l10n.photosPeopleVisible, color: c.erreur),
                    for (final issue in issues)
                      _Pill(
                        label: photoIssueLabel(l10n, issue),
                        color: c.attention,
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

/// A photo being sent (spinner) or whose upload failed ("Réessayer",
/// "Retirer").
class PendingPhotoTile extends StatelessWidget {
  const new({
    required this.preview,
    required this.failed,
    required this.onRetry,
    required this.onDiscard,
    super.key,
  });

  final Uint8List preview;
  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.realestyColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(RealestyRadius.field),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoImage(bytes: preview),
          ColoredBox(color: c.nuit.withValues(alpha: 0.55)),
          if (failed)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  l10n.photosUploadFailed,
                  textAlign: TextAlign.center,
                  style: RealestyTextStyles.caption.copyWith(color: c.surface),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RealestyIconButton(
                      icon: RealestyIcons.swap,
                      semanticLabel: l10n.photosRetry,
                      dark: true,
                      onPressed: onRetry,
                    ),
                    RealestyIconButton(
                      icon: RealestyIcons.trash,
                      semanticLabel: l10n.photosDiscard,
                      dark: true,
                      onPressed: onDiscard,
                    ),
                  ],
                ),
              ],
            )
          else
            Semantics(
              label: l10n.photosSending,
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.surface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const new({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: RealestyTextStyles.caption.copyWith(
            fontSize: 11,
            color: context.realestyColors.surface,
          ),
        ),
      ),
    );
  }
}
