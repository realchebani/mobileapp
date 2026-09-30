import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  const c = RealestyColors.light;

  group(ProvenanceTag, () {
    testWidgets('each kind has its label and colors', (tester) async {
      final expected = {
        ProvenanceKind.declared: (c.surface2, c.encre2),
        ProvenanceKind.document: (c.expertFond, c.expert),
        ProvenanceKind.externalSource: (c.expertFond, c.expert),
        ProvenanceKind.expertVerified: (c.vertTeinte, c.vertTexte),
        ProvenanceKind.aiEstimated: (c.attentionFond, c.attention),
      };
      for (final MapEntry(key: kind, value: (bg, fg)) in expected.entries) {
        await tester.pumpRealesty(ProvenanceTag(kind));
        final container = tester.widget<Container>(find.byType(Container));
        expect((container.decoration! as BoxDecoration).color, bg);
        final text = tester.widget<Text>(find.text(kind.defaultLabel));
        expect(text.style?.color, fg);
        final size = tester.getSize(find.byType(ProvenanceTag));
        expect(size.height, 20);
        final textWidth = tester.getSize(find.text(kind.defaultLabel)).width;
        expect(size.width, textWidth + 14);
      }
    });

    testWidgets('label can be overridden', (tester) async {
      await tester.pumpRealesty(
        const ProvenanceTag(ProvenanceKind.declared, label: 'Declared'),
      );
      expect(find.text('Declared'), findsOneWidget);
    });
  });
}
