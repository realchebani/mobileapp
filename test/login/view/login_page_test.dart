import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(loadRealestyFonts);

  group(LoginPage, () {
    testWidgets('renders the welcome and opens the e-mail login', (
      tester,
    ) async {
      final loginCubit = MockLoginCubit();
      when(() => loginCubit.state).thenReturn(const LoginState());
      final goRouter = MockGoRouter();
      when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);

      await tester.pumpApp(
        const LoginPage(),
        loginCubit: loginCubit,
        goRouter: goRouter,
      );

      expect(find.text('Bienvenue'), findsOneWidget);
      expect(find.textContaining('dossier audité par l’IA'), findsOneWidget);

      await tester.tap(find.text('Continuer avec un e-mail'));

      verify(loginCubit.editEmail).called(1);
      verify(() => goRouter.push<Object?>(AppRoutes.loginEmail)).called(1);
    });
  });
}
