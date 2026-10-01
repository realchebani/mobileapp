import 'package:flutter/services.dart';

/// Accepts a decimal of up to [maxIntegerDigits] digits and two decimals,
/// typed with a comma (a typed dot becomes one): "38,5".
class DecimalInputFormatter extends TextInputFormatter {
  const new({this.maxIntegerDigits = 4});

  final int maxIntegerDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll('.', ',');
    final valid = RegExp('^\\d{0,$maxIntegerDigits}(,\\d{0,2})?\$')
        .hasMatch(text);
    // Same length: the selection is kept.
    return valid ? newValue.copyWith(text: text) : oldValue;
  }
}

/// Accepts pool dimensions "8 × 4": digits, decimal separators, spaces and
/// a "×" (typed as x, X or *).
class DimensionsInputFormatter extends TextInputFormatter {
  const new();

  static const maxLength = 20;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp('[xX*]'), '×');
    final valid =
        text.length <= maxLength && RegExp(r'^[\d,. ×]*$').hasMatch(text);
    return valid ? newValue.copyWith(text: text) : oldValue;
  }
}
