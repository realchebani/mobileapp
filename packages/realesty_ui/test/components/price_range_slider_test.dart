import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(PriceRangeSlider, () {
    PriceRangeSlider slider({
      int value = 525000,
      ValueChanged<int>? onChanged,
    }) => PriceRangeSlider(
      low: 505000,
      high: 545000,
      value: value,
      onChanged: onChanged,
      lowLabel: 'bas',
      highLabel: 'haut',
      caption: 'Avis',
      semanticLabel: 'Prix',
    );

    test('track bounds and range', () {
      expect(slider().min, 429000);
      expect(slider().max, 627000);
      expect(slider().inRange, isTrue);
      expect(slider(value: 600000).inRange, isFalse);
      expect(slider(value: 500000).inRange, isFalse);
    });

    testWidgets('reports moves; labels; disabled', (tester) async {
      int? changed;
      await tester.pumpRealesty(
        SizedBox(width: 350, child: slider(onChanged: (v) => changed = v)),
      );
      expect(find.text('bas'), findsOneWidget);
      expect(find.text('Avis'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(-100, 0));
      expect(changed, lessThan(525000));
      expect(changed! % 1000, 0);
      await tester.pumpRealesty(SizedBox(width: 350, child: slider(value: 10)));
      expect(tester.widget<Slider>(find.byType(Slider)).value, 429000);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    });
  });
}
