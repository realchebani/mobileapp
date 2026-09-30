import 'dart:async';

import 'package:flutter/foundation.dart';

/// A [Listenable] notifying its listeners on every event of a stream, to
/// refresh a router when a bloc changes.
class StreamListenable extends ChangeNotifier {
  new(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
