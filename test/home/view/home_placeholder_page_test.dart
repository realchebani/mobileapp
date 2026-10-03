import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/home/home.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  late AppBloc appBloc;
  late MockGoRouter goRouter;

  setUp(() {
    appBloc = MockAppBloc();
    when(() => appBloc.state).thenReturn(const AppState());
    goRouter = MockGoRouter();
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  group(HomePlaceholderPage, () {
    testWidgets('renders the seller space and signs out', (tester) async {
      await tester.pumpApp(
        const HomePlaceholderPage(role: UserRole.seller),
        appBloc: appBloc,
      );

      expect(find.text('Bienvenue dans votre espace vendeur'), findsOneWidget);
      expect(find.text('Le parcours arrive bientôt.'), findsOneWidget);
      expect(find.text('Design system'), findsNothing);

      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
    });

    testWidgets('renders the buyer space with the gallery link', (
      tester,
    ) async {
      await tester.pumpApp(
        const HomePlaceholderPage(
          role: UserRole.buyer,
          showDesignSystemLink: true,
        ),
        goRouter: goRouter,
      );

      expect(find.text('Bienvenue dans votre espace acheteur'), findsOneWidget);

      await tester.tap(find.text('Design system'));
      verify(() => goRouter.push<Object?>(AppRoutes.designSystem)).called(1);
      await tester.tap(find.text('Supprimer mon compte'));
      verify(() => goRouter.push<Object?>(AppRoutes.accountDeletion)).called(1);
    });
  });
}
