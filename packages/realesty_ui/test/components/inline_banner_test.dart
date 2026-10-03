import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(InlineBanner, () {
    testWidgets('warning variant', (tester) async {
      await tester.pumpRealesty(const InlineBanner(message: 'Attention'));
      final container = tester.widget<Container>(find.byType(Container));
      expect((container.decoration! as BoxDecoration).color, c.attentionFond);
      expect(
        tester.widget<RealestyIcon>(find.byType(RealestyIcon)).color,
        c.attention,
      );
    });

    testWidgets('info variant', (tester) async {
      await tester.pumpRealesty(
        const InlineBanner(
          message: 'Info',
          variant: InlineBannerVariant.info,
          icon: RealestyIcons.spark,
        ),
      );
      final container = tester.widget<Container>(find.byType(Container));
      expect((container.decoration! as BoxDecoration).color, c.expertFond);
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.color, c.expert);
      expect(icon.icon, RealestyIcons.spark);
    });
  });
}
