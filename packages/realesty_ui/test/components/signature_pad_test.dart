import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(SignaturePad, () {
    late SignaturePadController controller;

    setUp(() => controller = SignaturePadController());
    tearDown(() => controller.dispose());

    Widget pad({bool enabled = true, bool hasError = false}) => SizedBox(
      width: 300,
      child: SignaturePad(
        controller: controller,
        hint: 'Signez',
        clearLabel: 'Effacer',
        semanticLabel: 'Zone',
        enabled: enabled,
        hasError: hasError,
      ),
    );

    testWidgets('draws, exports a PNG and clears', (tester) async {
      await tester.pumpRealesty(pad());
      expect(find.text('Signez'), findsOneWidget);
      expect(await controller.toPng(), isNull);
      await tester.drag(find.byType(CustomPaint).last, const Offset(80, 20));
      await tester.pump();
      expect(controller.isEmpty, isFalse);
      expect(controller.strokes, isNotEmpty);
      expect(find.text('Signez'), findsNothing);
      final png = await tester.runAsync(controller.toPng);
      expect(png, isNotNull);
      expect(png!.sublist(1, 4), 'PNG'.codeUnits);
      await tester.tap(find.text('Effacer'));
      await tester.pump();
      expect(controller.isEmpty, isTrue);
      expect(controller.strokes, isEmpty);
    });

    testWidgets('disabled pads ignore the finger', (tester) async {
      await tester.pumpRealesty(pad(enabled: false, hasError: true));
      await tester.drag(find.byType(CustomPaint).last, const Offset(80, 20));
      await tester.pump();
      expect(controller.isEmpty, isTrue);
    });

    testWidgets('follows a new controller', (tester) async {
      await tester.pumpRealesty(pad());
      final other = SignaturePadController();
      addTearDown(other.dispose);
      await tester.pumpRealesty(
        SizedBox(
          width: 300,
          child: SignaturePad(
            controller: other,
            hint: 'Signez',
            clearLabel: 'Effacer',
            semanticLabel: 'Zone',
          ),
        ),
      );
      await tester.drag(find.byType(CustomPaint).last, const Offset(80, 20));
      await tester.pump();
      expect(other.isEmpty, isFalse);
      expect(controller.isEmpty, isTrue);
    });
  });
}
