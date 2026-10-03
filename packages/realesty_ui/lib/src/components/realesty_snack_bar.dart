import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/icons/realesty_icon.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';

/// Shows a floating Realesty snackbar (encre background, white 14/500 text).
///
/// Error snackbars get a leading info icon in Erreur fond; other snackbars
/// show [icon] when given.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showRealestySnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  RealestyIcons? icon,
}) {
  final c = context.realestyColors;
  final glyph = isError ? icon ?? RealestyIcons.infoCircle : icon;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      content: Row(
        spacing: 10,
        children: [
          if (glyph != null)
            RealestyIcon(
              glyph,
              size: 18,
              color: isError ? c.erreurFond : c.surface,
            ),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
