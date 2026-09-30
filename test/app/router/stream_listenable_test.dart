import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';

void main() {
  group(StreamListenable, () {
    test('notifies on each event until disposed', () async {
      final controller = StreamController<int>.broadcast();
      final listenable = StreamListenable(controller.stream);
      var notifications = 0;
      listenable.addListener(() => notifications++);

      controller
        ..add(1)
        ..add(2);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 2);

      listenable.dispose();
      expect(controller.hasListener, isFalse);
      await controller.close();
    });
  });
}
