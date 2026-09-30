import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

InputDecoration _decoration(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).decoration!;

void main() {
  const c = RealestyColors.light;

  group(RealestyTextField, () {
    testWidgets('renders label, hint, icon and suffix', (tester) async {
      final changes = <String>[];
      await tester.pumpRealesty(
        RealestyTextField(
          label: 'Surface',
          hint: '0',
          leadingIcon: RealestyIcons.plan,
          suffixText: 'm²',
          onChanged: changes.add,
          footer: const ProvenanceTag(ProvenanceKind.declared),
        ),
      );
      expect(find.text('Surface'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('m²'), findsOneWidget);
      expect(find.byType(ProvenanceTag), findsOneWidget);
      expect(tester.getSize(find.byType(TextField)).height, 52);
      await tester.enterText(find.byType(TextField), '120');
      expect(changes, ['120']);
      final idle = _decoration(tester).enabledBorder! as OutlineInputBorder;
      expect(idle.borderSide.color, c.ligne);
      final focused = _decoration(tester).focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, c.encre);
      expect(focused.borderSide.width, 1.5);
    });

    testWidgets('error state shows the message and red borders', (
      tester,
    ) async {
      await tester.pumpRealesty(
        const RealestyTextField(label: 'E-mail', errorText: 'Invalide'),
      );
      expect(find.text('Invalide'), findsOneWidget);
      final idle = _decoration(tester).enabledBorder! as OutlineInputBorder;
      final focused = _decoration(tester).focusedBorder! as OutlineInputBorder;
      expect(idle.borderSide.color, c.erreur);
      expect(focused.borderSide.color, c.erreur);
      final icon = tester.widget<RealestyIcon>(find.byType(RealestyIcon));
      expect(icon.icon, RealestyIcons.infoCircle);
    });

    testWidgets('announces the label on the text field', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpRealesty(
        const RealestyTextField(label: 'Adresse', hint: 'Rue'),
      );
      expect(find.bySemanticsLabel(RegExp('Adresse')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('disabled state uses Surface 2', (tester) async {
      await tester.pumpRealesty(
        const RealestyTextField(label: 'Nom', enabled: false),
      );
      expect(_decoration(tester).fillColor, c.surface2);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style?.color, c.texteDiscret);
    });
  });
}
