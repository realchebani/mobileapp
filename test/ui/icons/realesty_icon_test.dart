import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

import '../helpers/pump_realesty.dart';

void main() {
  group(RealestyIcons, () {
    test('every icon has an SVG asset on the 24 grid', () {
      for (final icon in RealestyIcons.values) {
        final file = File(icon.assetPath);
        expect(file.existsSync(), isTrue, reason: icon.assetPath);
        final svg = file.readAsStringSync();
        expect(svg, contains('viewBox="0 0 24 24"'));
        expect(svg, contains('stroke-width="1.8"'));
        expect(svg, isNot(contains('<div')), reason: icon.assetPath);
      }
    });

    test('asset path uses the kebab-case file name', () {
      expect(
        File(RealestyIcons.mic.assetPath).readAsStringSync(),
        contains('<rect x="9" y="3" width="6" height="12" rx="3"/>'),
      );
      expect(
        RealestyIcons.chevronLeft.assetPath,
        'assets/icons/chevron-left.svg',
      );
    });
  });

  group(RealestyIcon, () {
    testWidgets('renders with the given size and color', (tester) async {
      await tester.pumpRealesty(
        const RealestyIcon(
          RealestyIcons.home,
          size: 22,
          color: Color(0xFF2E7D14),
          semanticLabel: 'Accueil',
        ),
      );
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 22);
      expect(
        svg.colorFilter,
        const ColorFilter.mode(Color(0xFF2E7D14), BlendMode.srcIn),
      );
      expect(find.bySemanticsLabel('Accueil'), findsOneWidget);
    });

    testWidgets('defaults to the icon theme color', (tester) async {
      await tester.pumpRealesty(
        const IconTheme(
          data: IconThemeData(color: Color(0xFF123456)),
          child: RealestyIcon(RealestyIcons.mic),
        ),
      );
      final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
      expect(svg.width, 20);
      expect(
        svg.colorFilter,
        const ColorFilter.mode(Color(0xFF123456), BlendMode.srcIn),
      );
      expect(svg.excludeFromSemantics, isTrue);
    });
  });
}
