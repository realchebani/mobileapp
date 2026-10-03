import 'package:flutter_test/flutter_test.dart';
import 'package:realesty_ui/realesty_ui.dart';

void main() {
  group('frenchNumber', () {
    test('groups thousands with a no-break space', () {
      expect(frenchNumber(525000), '525 000');
      expect(frenchNumber(1234567), '1 234 567');
      expect(frenchNumber(12), '12');
    });

    test('uses a decimal comma', () {
      expect(frenchNumber(1234.5, decimalDigits: 1), '1 234,5');
    });

    test('never outputs a narrow no-break space', () {
      expect(frenchNumber(987654321), isNot(contains(narrowNoBreakSpace)));
    });
  });

  test('withRenderableSpaces replaces U+202F', () {
    expect(withRenderableSpaces('525 000 €'), '525 000 €');
  });
}
