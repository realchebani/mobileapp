import 'package:flutter_test/flutter_test.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(RealestyListItem, () {
    testWidgets('tones color the leading tile', (tester) async {
      final expected = {
        RealestyListTileTone.neutral: c.encre,
        RealestyListTileTone.success: c.vertTexte,
        RealestyListTileTone.error: c.erreur,
      };
      for (final MapEntry(key: tone, value: color) in expected.entries) {
        await tester.pumpRealesty(
          RealestyListItem(
            title: 'Titre',
            subtitle: 'Sous-titre',
            leadingIcon: RealestyIcons.file,
            tone: tone,
            trailing: const RealestyBadge(label: 'Badge'),
          ),
        );
        expect(
          tester.widget<RealestyIcon>(find.byType(RealestyIcon)).color,
          color,
        );
      }
      expect(find.text('Sous-titre'), findsOneWidget);
      expect(find.text('Badge'), findsOneWidget);
      expect(
        tester.getSize(find.byType(RealestyListItem)).height,
        greaterThanOrEqualTo(56),
      );
    });

    testWidgets('tappable without divider', (tester) async {
      var taps = 0;
      await tester.pumpRealesty(
        RealestyListItem(
          title: 'Dernier',
          showDivider: false,
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.text('Dernier'));
      expect(taps, 1);
      expect(find.byType(RealestyIcon), findsNothing);
    });
  });
}
