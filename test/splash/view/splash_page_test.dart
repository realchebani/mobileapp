import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/splash/splash.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  late ProfileCubit profileCubit;
  late AppBloc appBloc;

  setUpAll(() => registerFallbackValue(const AppLogoutPressed()));

  setUp(() {
    profileCubit = MockProfileCubit();
    appBloc = MockAppBloc();
    when(() => appBloc.state).thenReturn(const AppState());
  });

  group(SplashPage, () {
    testWidgets('renders the logo, tagline and progress', (tester) async {
      when(() => profileCubit.state)
          .thenReturn(const ProfileState(status: ProfileStatus.loading));
      await tester.pumpApp(const SplashPage(), profileCubit: profileCubit);
      await tester.pumpAndSettle();

      expect(find.byType(RealestyLogo), findsOneWidget);
      expect(
        find.textContaining('pas vos économies.', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('L’immobilier sécurisé à 1 %'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('offers to retry or sign out when the profile failed', (
      tester,
    ) async {
      whenListen(
        profileCubit,
        const Stream<ProfileState>.empty(),
        initialState: const ProfileState(status: ProfileStatus.failure),
      );
      await tester.pumpApp(
        const SplashPage(),
        profileCubit: profileCubit,
        appBloc: appBloc,
      );

      expect(find.text('Impossible de charger votre profil.'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      verify(() => profileCubit.retry()).called(1);

      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
    });
  });
}
