import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

import '../../helpers/helpers.dart';

void main() {
  group(TunnelScaffold, () {
    testWidgets('lays out the header, body and action bar', (tester) async {
      usePhoneSurface();
      await tester.pumpApp(
        TunnelScaffold(
          header: const Text('header'),
          actionBar: const Text('bar'),
          children: [for (var i = 0; i < 30; i++) Text('item $i')],
        ),
      );

      expect(find.text('header'), findsOneWidget);
      expect(find.text('item 0'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('bar')).dy,
        greaterThan(tester.getBottomLeft(find.text('item 0')).dy),
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('works without header and action bar', (tester) async {
      await tester.pumpApp(const TunnelScaffold(children: [Text('only')]));
      expect(find.text('only'), findsOneWidget);
    });
  });
}
