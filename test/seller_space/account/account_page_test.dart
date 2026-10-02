import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  late MockAppBloc appBloc;
  late MockProfileCubit profileCubit;
  late MockGoRouter goRouter;

  setUp(() {
    appBloc = MockAppBloc();
    when(() => appBloc.state).thenReturn(
      const AppState.authenticated(
        AuthUser(id: 'user-id', email: 'sophie@example.com'),
      ),
    );
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(
      const ProfileState(
        profile: Profile(id: 'user-id', firstName: 'Sophie'),
      ),
    );
    goRouter = MockGoRouter();
    when(() => goRouter.push<Object?>(any())).thenAnswer((_) async => null);
  });

  group(AccountPage, () {
    testWidgets('shows the owner, signs out and opens the design system', (
      tester,
    ) async {
      await tester.pumpSellerSpacePage(
        const AccountPage(showDesignSystemLink: true),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: testProperty,
            owners: [
              PropertyOwner(
                propertyId: 'property-id',
                position: 2,
                firstName: 'Marc',
                lastName: 'Durand',
              ),
              PropertyOwner(
                propertyId: 'property-id',
                position: 1,
                firstName: 'Sophie',
                lastName: 'Durand',
              ),
            ],
          ),
        ),
        appBloc: appBloc,
        profileCubit: profileCubit,
        goRouter: goRouter,
      );
      expect(find.text('Sophie Durand'), findsOneWidget);
      expect(find.text('SD'), findsOneWidget);
      expect(find.text('sophie@example.com'), findsOneWidget);
      expect(find.text('Lien de connexion par e-mail'), findsOneWidget);

      await tester.ensureVisible(find.text('Se déconnecter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
      await tester.ensureVisible(find.text('Design system'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Design system'));
      verify(() => goRouter.push<Object?>(AppRoutes.designSystem)).called(1);
    });

    testWidgets('falls back on the profile first name', (tester) async {
      await tester.pumpSellerSpacePage(
        const AccountPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: testProperty,
            owners: [
              PropertyOwner(
                propertyId: 'property-id',
                position: 1,
                firstName: ' ',
                lastName: '',
              ),
            ],
          ),
        ),
        appBloc: appBloc,
        profileCubit: profileCubit,
      );
      expect(find.text('Sophie'), findsOneWidget);
      expect(find.text('Design system'), findsNothing);
    });

    testWidgets('without any name', (tester) async {
      when(() => profileCubit.state).thenReturn(const ProfileState());
      await tester.pumpSellerSpacePage(
        const AccountPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(),
        profileCubit: profileCubit,
      );
      expect(find.text('Mon profil'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('turns the AI suggestions on the photos off and on', (
      tester,
    ) async {
      usePhoneSurface();
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
      );
      await tester.pumpApp(
        const AccountPage(),
        appBloc: appBloc,
        profileCubit: profileCubit,
        photoServices: services,
      );
      expect(find.text('Suggestions de l’IA sur les photos'), findsOneWidget);
      await tester.tap(find.text('Activées · touchez pour les désactiver'));
      await tester.pumpAndSettle();
      expect(services.preferences!.consent, PhotoAnalysisConsent.declined);
      await tester.tap(find.text('Désactivées · touchez pour les activer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('J’accepte l’analyse'));
      await tester.pumpAndSettle();
      expect(services.preferences!.consent, PhotoAnalysisConsent.given);
      expect(
        find.text('Activées · touchez pour les désactiver'),
        findsOneWidget,
      );
    });

    testWidgets('no AI item without the vision AI', (tester) async {
      await tester.pumpApp(
        const AccountPage(),
        appBloc: appBloc,
        profileCubit: profileCubit,
      );
      expect(find.text('Suggestions de l’IA sur les photos'), findsNothing);
    });
  });
}
