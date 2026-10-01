import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/icons/realesty_icon.dart';
import 'package:mobileapp/ui/tokens/realesty_colors.dart';
import 'package:mobileapp/ui/tokens/realesty_dimens.dart';
import 'package:mobileapp/ui/typography/realesty_text_styles.dart';

/// Labelled Realesty text field (box 52 high, radius 12).
///
/// States: focus (1.5 encre border), error (1.5 erreur border and message
/// with an info icon below), disabled (Surface 2 fill, muted text).
class RealestyTextField extends StatelessWidget {
  const new({
    required this.label,
    this.hint,
    this.leadingIcon,
    this.suffixText,
    this.errorText,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.autofillHints,
    this.obscureText = false,
    this.autofocus = false,
    this.enabled = true,
    this.maxLines = 1,
    this.footer,
    super.key,
  });

  /// Label shown above the box (13/600, Encre 2).
  final String label;

  /// Placeholder text.
  final String? hint;

  /// 18px icon at the start of the box.
  final RealestyIcons? leadingIcon;

  /// Unit shown at the end of the box (e.g. "m²", "€").
  final String? suffixText;

  /// Error message; when set the field shows its error state.
  final String? errorText;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool autofocus;
  final bool enabled;

  /// Lines the field grows to (from one) before scrolling; long values
  /// wrap instead of scrolling horizontally when above 1.
  final int maxLines;

  /// Optional widget below the box, e.g. a provenance tag.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    final hasError = errorText != null;
    final muted = colors.texteDiscret;

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(RealestyRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
    final idle = hasError
        ? border(colors.erreur, RealestyBorders.medium)
        : border(colors.ligne, RealestyBorders.thin);
    final focused = hasError
        ? border(colors.erreur, RealestyBorders.medium)
        : border(colors.encre, RealestyBorders.medium);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: RealestyTextStyles.label.copyWith(color: colors.encre2),
          ),
        ),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            inputFormatters: inputFormatters,
            autofillHints: autofillHints,
            obscureText: obscureText,
            autofocus: autofocus,
            enabled: enabled,
            minLines: maxLines > 1 ? 1 : null,
            maxLines: maxLines,
            style: RealestyTextStyles.body.copyWith(
              color: enabled ? colors.encre : muted,
            ),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: enabled ? colors.surface : colors.surface2,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(
                leadingIcon == null ? 14 : 0,
                14,
                suffixText == null ? 14 : 0,
                14,
              ),
              prefixIcon: leadingIcon == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 14, right: 10),
                      child: RealestyIcon(leadingIcon!, size: 18, color: muted),
                    ),
              prefixIconConstraints: const BoxConstraints(),
              suffixIcon: suffixText == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: 10, right: 14),
                      child: Text(
                        suffixText!,
                        style: RealestyTextStyles.body.copyWith(
                          fontSize: 15,
                          color: muted,
                        ),
                      ),
                    ),
              suffixIconConstraints: const BoxConstraints(),
              enabledBorder: idle,
              disabledBorder: border(colors.ligne, RealestyBorders.thin),
              focusedBorder: focused,
            ),
          ),
        ),
        if (hasError)
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: RealestyIcon(
                    RealestyIcons.infoCircle,
                    size: 14,
                    color: colors.erreur,
                  ),
                ),
                Expanded(
                  child: Text(
                    errorText!,
                    style: RealestyTextStyles.fieldError.copyWith(
                      color: colors.erreur,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ?footer,
      ],
    );
  }
}
