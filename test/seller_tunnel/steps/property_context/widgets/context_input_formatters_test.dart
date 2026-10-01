import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/context_input_formatters.dart';

const _nbsp = ' ';

TextEditingValue _value(String text, [int? cursor]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: cursor ?? text.length),
);

void main() {
  group('AmountInputFormatter', () {
    const formatter = AmountInputFormatter();

    TextEditingValue format(TextEditingValue old, TextEditingValue value) =>
        formatter.formatEditUpdate(old, value);

    test('groups the digits and keeps the cursor after the same digit', () {
      expect(
        format(_value('32000'), _value('320000')),
        _value('320${_nbsp}000'),
      );
      // Typing "5" after "3" in "320 000".
      expect(
        format(_value('320${_nbsp}000', 1), _value('3520${_nbsp}000', 2)),
        _value('3${_nbsp}520${_nbsp}000', 3),
      );
    });

    test('drops non-digits and leading zeros', () {
      expect(format(_value(''), _value('0a12')), _value('12'));
      expect(format(_value(''), _value('0')), _value('0'));
    });

    test('empties the field without digits', () {
      expect(format(_value('1'), _value('')), TextEditingValue.empty);
    });

    test('rejects more than the maximum of digits', () {
      final old = _value('123${_nbsp}456${_nbsp}789');
      expect(format(old, _value('${old.text}0')), old);
    });

    test('drops decimals', () {
      expect(format(_value(''), _value('320000.50')), _value('320${_nbsp}000'));
      expect(
        format(_value(''), _value('320 000,5', 3)),
        _value('320${_nbsp}000', 3),
      );
      expect(format(_value('12'), _value('12,')), _value('12'));
    });

    test('forward delete on a separator removes the digit after it', () {
      expect(
        format(_value('320${_nbsp}000', 3), _value('320000', 3)),
        _value('32${_nbsp}000', 4),
      );
    });

    test('backspace on a separator removes the digit before it', () {
      expect(
        format(_value('320${_nbsp}000', 4), _value('320000', 3)),
        _value('32${_nbsp}000', 2),
      );
    });
  });

  group('MonthInputFormatter', () {
    const formatter = MonthInputFormatter();

    TextEditingValue format(String old, String text) =>
        formatter.formatEditUpdate(_value(old), _value(text));

    test('adds the slash after the month', () {
      expect(format('0', '05'), _value('05/'));
      expect(format('05/', '05/2'), _value('05/2'));
      expect(format('', '052020'), _value('05/2020'));
      expect(format('', 'a5'), _value('5'));
    });

    test('deleting the slash also deletes the digit before it', () {
      expect(format('05/', '05'), _value('0'));
      expect(format('05/2', '05/'), _value('05'));
    });

    test('normalizes pasted months', () {
      expect(format('', '5/2024'), _value('05/2024'));
      expect(format('', '05/2024'), _value('05/2024'));
      expect(format('', '2024-05'), _value('05/2024'));
      expect(format('', '2024-5'), _value('05/2024'));
      expect(format('', '052024'), _value('05/2024'));
      expect(format('3', '3/'), _value('03/'));
    });

    test('keeps the cursor after the same digit', () {
      // Typing "1" before "2" in "05/2024" → "05/12024" is too long.
      expect(
        formatter.formatEditUpdate(_value('05/202', 3), _value('05/1202', 4)),
        _value('05/1202', 4),
      );
      expect(
        formatter.formatEditUpdate(_value('05/2024', 1), _value('5/2024', 0)),
        _value('05/2024'),
      );
      expect(
        formatter.formatEditUpdate(_value('052', 3), _value('0520', 1)),
        _value('05/20', 1),
      );
    });

    test('rejects more than a month and a year', () {
      expect(format('05/2020', '05/20201'), _value('05/2020'));
    });
  });
}
