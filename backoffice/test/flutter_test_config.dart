import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/helpers.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  registerFallbackValue(DossierScope.all);
  registerFallbackValue(StaffRole.expert);
  registerFallbackValue(<String, dynamic>{});
  registerFallbackValue(<FileRequest>[]);
  registerFallbackValue(DateTime(2026));
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadRealestyFonts();
  await testMain();
}
