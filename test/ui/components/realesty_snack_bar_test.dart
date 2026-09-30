import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group('showRealestySnackBar', () {
    Future<void> show(
      WidgetTester tester, {
      bool isError = false,
      RealestyIcons? icon,
    }) async {
      await tester.pumpRealesty(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showRealestySnackBar(
              context,
              'Message',
              isError: isError,
              icon: icon,
            ),
            child: const Text('Show'),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pump();
    }

    testWidgets('shows a floating message without icon', (tester) async {
      await show(tester);
      expect(find.text('Message'), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.behavior, isNull);
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(SnackBar),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        c.encre,
      );
      expect(find.byType(RealestyIcon), findsNothing);
    });

    testWidgets('error variant has the info icon', (tester) async {
      await show(tester, isError: true);
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.icon, RealestyIcons.infoCircle);
      expect(icon.color, c.erreurFond);
    });

    testWidgets('custom icon', (tester) async {
      await show(tester, icon: RealestyIcons.check);
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.icon, RealestyIcons.check);
      expect(icon.color, c.surface);
    });
  });
}
