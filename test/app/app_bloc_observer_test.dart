import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';

import '../helpers/helpers.dart';

void main() {
  group(AppBlocObserver, () {
    test('can be created with the default logger', () {
      expect(const AppBlocObserver(), isA<BlocObserver>());
    });

    test('logs changes and errors', () {
      final messages = <String>[];
      final observer = AppBlocObserver(log: messages.add);
      final cubit = MockLoginCubit();

      observer
        ..onChange(cubit, const Change(currentState: 0, nextState: 1))
        ..onError(cubit, Exception('oops'), StackTrace.empty);

      expect(messages, [
        contains('onChange(MockLoginCubit'),
        contains('onError(MockLoginCubit, Exception: oops'),
      ]);
    });
  });
}
