import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/widgets/technical_input_formatters.dart';

TextEditingValue _value(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group(DecimalInputFormatter, () {
    const formatter = DecimalInputFormatter();
    String format(String old, String typed) =>
        formatter.formatEditUpdate(_value(old), _value(typed)).text;

    test('accepts decimals with a comma', () {
      expect(format('38', '38.'), '38,');
      expect(format('38,', '38,5'), '38,5');
      expect(format('38,25', '38,251'), '38,25');
      expect(format('1234', '12345'), '1234');
      expect(format('12', '12a'), '12');
    });
  });

  group(DimensionsInputFormatter, () {
    const formatter = DimensionsInputFormatter();
    String format(String old, String typed) =>
        formatter.formatEditUpdate(_value(old), _value(typed)).text;

    test('accepts "length × width"', () {
      expect(format('8 ', '8 x'), '8 ×');
      expect(format('8', '8*4'), '8×4');
      expect(format('8', '8a'), '8');
      expect(format('', '1' * 21), '');
    });
  });
}
