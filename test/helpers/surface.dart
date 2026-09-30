import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders tests on a 390×844 phone surface (the design artboards), for
/// the current test.
void usePhoneSurface() {
  final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(view.reset);
}
