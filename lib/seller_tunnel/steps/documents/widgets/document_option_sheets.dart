import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/ui/ui.dart';

/// Where "Importer" takes a document from.
enum DocumentImportSource {
  /// A PDF or image from the files.
  files,

  /// An image from the photo library.
  photos,

  /// A document of another property of the seller (copied, EPIC-13).
  otherProperty,
}

/// "Importer": files (PDF, images), the photo library or, when the seller
/// has [otherProperties], another property. Returns null when dismissed.
Future<DocumentImportSource?> showDocumentSourceSheet(
  BuildContext context, {
  bool otherProperties = false,
}) {
  final l10n = context.l10n;
  return _showOptionSheet(
    context,
    title: l10n.documentsSourceSheetTitle,
    options: [
      DocumentOption(
        value: DocumentImportSource.files,
        title: l10n.documentsSourceFiles,
        subtitle: l10n.documentsSourceFilesSubtitle,
        icon: RealestyIcons.file,
      ),
      DocumentOption(
        value: DocumentImportSource.photos,
        title: l10n.documentsSourcePhotos,
        subtitle: l10n.documentsSourcePhotosSubtitle,
        icon: RealestyIcons.camera,
      ),
      if (otherProperties)
        DocumentOption(
          value: DocumentImportSource.otherProperty,
          title: l10n.documentsReuseOption,
          subtitle: l10n.documentsReuseOptionSubtitle,
          icon: RealestyIcons.swap,
        ),
    ],
  );
}

Future<T?> _showOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<DocumentOption<T>> options,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) =>
        DocumentOptionSheet<T>(title: title, options: options),
  );
}

/// An option of a [DocumentOptionSheet].
final class DocumentOption<T> {
  const new({
    required this.value,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final T value;
  final String title;
  final String? subtitle;
  final RealestyIcons icon;
}

/// A titled list of options; tapping one closes the sheet with its value.
class DocumentOptionSheet<T> extends StatelessWidget {
  const new({required this.title, required this.options, super.key});

  final String title;
  final List<DocumentOption<T>> options;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RealestySpacing.gutter,
        0,
        RealestySpacing.gutter,
        RealestySpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: RealestySpacing.xs),
            child: Semantics(
              header: true,
              child: Text(title, style: RealestyTextStyles.title2),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (index, option) in options.indexed)
                  RealestyListItem(
                    title: option.title,
                    subtitle: option.subtitle,
                    leadingIcon: option.icon,
                    showDivider: index < options.length - 1,
                    trailing: RealestyIcon(
                      RealestyIcons.chevronRight,
                      size: 18,
                      color: context.realestyColors.texteDiscret,
                    ),
                    onTap: () => Navigator.of(context).pop(option.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
