import 'package:flutter/services.dart';
import 'package:mobileapp/ui/ui.dart';

final _nonDigit = RegExp(r'\D');

/// The offset in [formatted] just after its [digits]-th digit.
int _offsetAfterDigits(String formatted, int digits) {
  var offset = 0;
  for (var seen = 0; seen < digits && offset < formatted.length; offset++) {
    if (!_nonDigit.hasMatch(formatted[offset])) seen++;
  }
  return offset;
}

/// Keeps the euros of an amount and groups them the French way
/// ("320 000"), keeping the cursor after the same digit. Decimals
/// ("320000.50", "320 000,50") are dropped.
class AmountInputFormatter extends TextInputFormatter {
  const new({this.maxDigits = 9});

  final int maxDigits;

  /// One or two decimals (or a lone separator) at the end.
  static final _decimals = RegExp(r'[.,]\d{0,2}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    var cursor = newValue.selection.baseOffset.clamp(0, text.length);
    final oldDigits = oldValue.text.replaceAll(_nonDigit, '');
    // Deleting a group separator deletes the digit next to it: before it
    // (backspace, the cursor moved) or after it (forward delete).
    if (text.length < oldValue.text.length &&
        text.replaceAll(_nonDigit, '') == oldDigits) {
      if (oldValue.selection.baseOffset == cursor && cursor < text.length) {
        text = text.substring(0, cursor) + text.substring(cursor + 1);
      } else if (cursor > 0) {
        text = text.substring(0, cursor - 1) + text.substring(cursor);
        cursor--;
      }
    }
    final decimals = _decimals.firstMatch(text);
    if (decimals != null) {
      text = text.substring(0, decimals.start);
      if (cursor > text.length) cursor = text.length;
    }
    var digits = text.replaceAll(_nonDigit, '');
    final digitsBeforeCursor = text
        .substring(0, cursor)
        .replaceAll(_nonDigit, '')
        .length;
    digits = digits.replaceFirst(RegExp('^0+(?=.)'), '');
    if (digits.length > maxDigits) return oldValue;
    if (digits.isEmpty) return TextEditingValue.empty;
    final formatted = frenchNumber(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _offsetAfterDigits(formatted, digitsBeforeCursor),
      ),
    );
  }
}

/// Formats a month as `mm/aaaa` while typing: the slash is added after the
/// month, a one-digit month followed by "/" gets its zero ("3/" → "03/"),
/// and pasted "5/2024", "2024-05" or "052024" become "05/2024".
class MonthInputFormatter extends TextInputFormatter {
  const new();

  static final _isoMonth = RegExp(r'^(\d{4})-(\d{1,2})$');
  static final _shortMonth = RegExp(r'^(\d)/(\d{0,4})$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final input = newValue.text.trim();
    final normalized = switch ((
      _isoMonth.firstMatch(input),
      _shortMonth.firstMatch(input),
    )) {
      (final iso?, _) => '${iso[2]!.padLeft(2, '0')}/${iso[1]}',
      (_, final short?) => '0${short[1]}/${short[2]}',
      _ => null,
    };
    if (normalized != null) {
      return TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }

    var digits = newValue.text.replaceAll(_nonDigit, '');
    // Deleting the slash also deletes the month digit before it.
    if (oldValue.text.endsWith('/') &&
        newValue.text.length < oldValue.text.length &&
        digits.length == 2) {
      digits = digits.substring(0, 1);
    }
    if (digits.length > 6) return oldValue;
    final text =
        digits.length > 2 ||
            (digits.length == 2 && newValue.text.length > oldValue.text.length)
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    final cursor = newValue.selection.baseOffset;
    final offset = cursor < 0 || cursor >= newValue.text.length
        ? text.length
        : _offsetAfterDigits(
            text,
            newValue.text.substring(0, cursor).replaceAll(_nonDigit, '').length,
          );
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
