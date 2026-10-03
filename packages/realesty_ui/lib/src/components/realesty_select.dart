import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/src/components/realesty_pressable.dart';
import 'package:realesty_ui/src/icons/realesty_icon.dart';
import 'package:realesty_ui/src/tokens/realesty_colors.dart';
import 'package:realesty_ui/src/tokens/realesty_dimens.dart';
import 'package:realesty_ui/src/typography/realesty_text_styles.dart';

/// An option of a [RealestySelect].
@immutable
class RealestySelectOption<T> {
  const new({required this.value, required this.label});

  final T value;
  final String label;
}

/// Labelled select box: value on the left, chevron on the right. Tapping it
/// opens a bottom sheet listing [options].
class RealestySelect<T> extends StatelessWidget {
  const new({
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.hint,
    this.leadingIcon,
    this.sheetTitle,
    super.key,
  });

  final String label;
  final List<RealestySelectOption<T>> options;

  /// Called with the picked value; null disables the select.
  final ValueChanged<T>? onChanged;

  /// Currently selected value.
  final T? value;

  /// Placeholder when nothing is selected.
  final String? hint;

  final RealestyIcons? leadingIcon;

  /// Title of the bottom sheet; defaults to [label].
  final String? sheetTitle;

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<RealestySelectOption<T>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _RealestySelectSheet<T>(
        title: sheetTitle ?? label,
        options: options,
        value: value,
      ),
    );
    if (picked != null) onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
    final selected = options.where((o) => o.value == value).firstOrNull;
    return RealestyPressable(
      onPressed: onChanged == null ? null : () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Text(
            label,
            style: RealestyTextStyles.label.copyWith(color: colors.encre2),
          ),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(RealestyRadius.field),
              border: Border.all(color: colors.ligne),
            ),
            child: Row(
              spacing: 10,
              children: [
                if (leadingIcon != null)
                  RealestyIcon(
                    leadingIcon!,
                    size: 18,
                    color: colors.texteDiscret,
                  ),
                Expanded(
                  child: Text(
                    selected?.label ?? hint ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RealestyTextStyles.body.copyWith(
                      color: selected == null
                          ? colors.placeholder
                          : colors.encre,
                    ),
                  ),
                ),
                RealestyIcon(
                  RealestyIcons.chevronDown,
                  size: 18,
                  color: colors.texteDiscret,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RealestySelectSheet<T> extends StatelessWidget {
  const new({required this.title, required this.options, required this.value});

  final String title;
  final List<RealestySelectOption<T>> options;
  final T? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.realestyColors;
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
                  RealestyPressable(
                    selected: option.value == value,
                    onPressed: () => Navigator.of(context).pop(option),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 52),
                      decoration: BoxDecoration(
                        border: index == options.length - 1
                            ? null
                            : Border(
                                bottom: BorderSide(color: colors.bordureCarte),
                              ),
                      ),
                      child: Row(
                        spacing: RealestySpacing.sm,
                        children: [
                          Expanded(
                            child: Text(
                              option.label,
                              style: RealestyTextStyles.body.copyWith(
                                color: colors.encre,
                                fontWeight: option.value == value
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (option.value == value)
                            RealestyIcon(
                              RealestyIcons.check,
                              color: colors.vertTexte,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
