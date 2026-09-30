import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(RealestyBadge, () {
    testWidgets('every variant renders with its colors', (tester) async {
      final expected = {
        RealestyBadgeVariant.essentiel: (c.essentielFond, c.essentiel),
        RealestyBadgeVariant.premium: (c.premiumFond, c.premium),
        RealestyBadgeVariant.expert: (c.expertFond, c.expert),
        RealestyBadgeVariant.compatibility: (c.encre, c.lueur),
        RealestyBadgeVariant.passVisite: (c.encre, c.surface),
        RealestyBadgeVariant.certified: (c.vertTeinte, c.vertTexte),
        RealestyBadgeVariant.toComplete: (c.attentionFond, c.attention),
        RealestyBadgeVariant.missing: (c.erreurFond, c.erreur),
        RealestyBadgeVariant.neutral: (c.surface2, c.encre2),
      };
      for (final MapEntry(key: variant, value: (bg, fg)) in expected.entries) {
        await tester.pumpRealesty(
          RealestyBadge(label: variant.name, variant: variant),
        );
        final container = tester.widget<Container>(find.byType(Container));
        expect((container.decoration! as BoxDecoration).color, bg);
        final text = tester.widget<Text>(find.text(variant.name));
        expect(text.style?.color, fg);
        expect(
          find.byType(RealestyIcon),
          variant.defaultIcon == null ? findsNothing : findsOneWidget,
        );
        expect(tester.getSize(find.byType(RealestyBadge)).height, 26);
      }
    });

    testWidgets('compatibility uses Sora', (tester) async {
      await tester.pumpRealesty(
        const RealestyBadge(
          label: '94 %',
          variant: RealestyBadgeVariant.compatibility,
        ),
      );
      expect(
        tester.widget<Text>(find.text('94 %')).style?.fontFamily,
        RealestyFonts.sora,
      );
    });

    testWidgets('icon can be overridden or hidden', (tester) async {
      await tester.pumpRealesty(
        const RealestyBadge(
          label: 'Économies',
          variant: RealestyBadgeVariant.certified,
          icon: RealestyIcons.trending,
        ),
      );
      expect(
        tester.widget<RealestyIcon>(find.byType(RealestyIcon)).icon,
        RealestyIcons.trending,
      );
      await tester.pumpRealesty(
        const RealestyBadge(
          label: 'Sans icône',
          variant: RealestyBadgeVariant.essentiel,
          showIcon: false,
        ),
      );
      expect(find.byType(RealestyIcon), findsNothing);
    });
  });
}
