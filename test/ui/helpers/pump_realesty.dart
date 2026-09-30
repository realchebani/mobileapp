import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/ui/ui.dart';

extension PumpRealesty on WidgetTester {
  /// Pumps [widget] centered in a [Scaffold] under the Realesty theme.
  Future<void> pumpRealesty(Widget widget) {
    return pumpWidget(
      MaterialApp(
        theme: realestyTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(20), child: widget),
          ),
        ),
      ),
    );
  }
}
