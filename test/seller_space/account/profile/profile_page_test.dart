import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';
import '../../pump_seller_space.dart';
import '../../vault/vault_fixtures.dart';

void main() {
  const profile = Profile(id: 'user-id', firstName: 'Sophie');
  late MockAppBloc appBloc;
  late MockProfileCubit profileCubit;
  late MockProfileRepository repository;
  late MockGoRouter router;

  setUpAll(() {
    registerFallbackValue(const ProfileDetails());
    registerFallbackValue(profile);
  });
  setUpAll(loadRealestyFonts);

  setUp(() {
    appBloc = MockAppBloc();
    when(() => appBloc.state).thenReturn(
      const AppState.authenticated(
        AuthUser(id: 'user-id', email: 'sophie@example.com'),
      ),
    );
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(
      const ProfileState(status: ProfileStatus.success, profile: profile),
    );
    repository = MockProfileRepository();
    router = MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
    when(() => router.push<Object?>(any())).thenAnswer((_) async => null);
    when(() => router.canPop()).thenReturn(true);
    when(router.pop).thenReturn(null);
  });

  Future<void> pump(WidgetTester tester, {SellerTunnelState? tunnel}) async {
    usePhoneSurface();
    tester.view.physicalSize = const Size(390, 1800);
    await tester.pumpSellerSpacePage(
      RepositoryProviderValue(repository: repository),
      sellerTunnelCubit: mockSellerTunnelCubit(
        tunnel ??
            SellerTunnelState(
              status: SellerTunnelStatus.success,
              property: sentProperty,
              owners: const [sophie, marc],
              documents: [
                document(
                  'id',
                  kind: DocumentKind.identityDocument,
                  ownerRef: 'owner-1',
                ),
              ],
            ),
      ),
      appBloc: appBloc,
      profileCubit: profileCubit,
      goRouter: router,
    );
    await tester.pumpAndSettle();
  }

  group(ProfilePage, () {
    testWidgets('shows the information, owners and security', (tester) async {
      await pump(tester);
      expect(find.text('Informations & sécurité'), findsOneWidget);
      expect(find.text('sophie@example.com'), findsOneWidget);
      expect(find.text('Sophie Durand (vous)'), findsOneWidget);
      expect(find.text('Pièce reçue'), findsNWidgets(2));
      expect(find.text('À ajouter'), findsOneWidget);
      await tester.tap(find.text('Marc Durand'));
      verify(
        () => router.go(
          AppRoutes.sellerVaultProperty('property-id', rubric: 'identite'),
        ),
      ).called(1);
      await tester.tap(find.text('Pièce d’identité'));
      verify(
        () => router.go(
          AppRoutes.sellerVaultProperty('property-id', rubric: 'identite'),
        ),
      ).called(1);
      await tester.tap(find.text('Supprimer mon compte'));
      verify(() => router.push<Object?>(AppRoutes.accountDeletion)).called(1);
      // Nothing changed: back at once.
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(router.pop).called(1);
    });

    testWidgets('validates, then saves', (tester) async {
      const saved = Profile(
        id: 'user-id',
        firstName: 'Sophie',
        phone: '0612345678',
      );
      when(() => repository.updateDetails(any(), any()))
          .thenAnswer((_) async => saved);
      await pump(tester);
      await tester.enterText(find.byType(TextField).at(3), 'abc');
      await tester.tap(find.text('Enregistrer les modifications'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez un numéro de téléphone valide.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(3), '0612345678');
      await tester.tap(find.text('Enregistrer les modifications'));
      await tester.pumpAndSettle();
      verify(() => profileCubit.profileUpdated(saved)).called(1);
      expect(find.text('Vos informations sont enregistrées.'), findsOneWidget);
    });

    testWidgets('reports a failed save; asks before leaving', (tester) async {
      when(() => repository.updateDetails(any(), any()))
          .thenThrow(const UpdateProfileFailure());
      await pump(tester);
      await tester.enterText(find.byType(TextField).at(1), 'Durand');
      await tester.enterText(find.byType(TextField).first, 'Sophia');
      await tester.enterText(find.byType(TextField).last, '1 rue');
      await tester.tap(find.text('Enregistrer les modifications'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Vos informations n’ont pas pu être enregistrées. Réessayez.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.pumpAndSettle();
      expect(find.text('Quitter sans enregistrer ?'), findsOneWidget);
      await tester.tap(find.text('Continuer la saisie'));
      await tester.pumpAndSettle();
      verifyNever(router.pop);
      // The system back gesture asks too.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitter sans enregistrer'));
      await tester.pumpAndSettle();
      verify(router.pop).called(1);
    });

    testWidgets('scrolls to a too long name', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField).at(1), 'x' * 101);
      await tester.tap(find.text('Enregistrer les modifications'));
      await tester.pumpAndSettle();
      expect(find.text('Ce texte est trop long.'), findsOneWidget);
    });

    testWidgets('without a property nor a name', (tester) async {
      when(() => profileCubit.state).thenReturn(
        const ProfileState(
          status: ProfileStatus.success,
          profile: Profile(id: 'user-id'),
        ),
      );
      await pump(tester, tunnel: const SellerTunnelState());
      expect(find.text('?'), findsOneWidget);
      expect(find.text('Propriétaires du bien'.toUpperCase()), findsNothing);
      expect(find.text('Pièce d’identité'), findsNothing);
    });

    testWidgets('missing identity documents', (tester) async {
      await pump(
        tester,
        tunnel: const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: sentProperty,
          owners: [sophie],
        ),
      );
      expect(find.text('À ajouter'), findsNWidgets(2));
    });

    testWidgets('every identity document received', (tester) async {
      await pump(
        tester,
        tunnel: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: sentProperty,
          owners: const [sophie],
          documents: [
            document('id', kind: DocumentKind.identityDocument),
            document('deed', kind: DocumentKind.titleDeed),
          ],
        ),
      );
      expect(find.text('Pièce reçue'), findsNWidgets(2));
    });

    testWidgets('the main owner when the profile is no owner', (tester) async {
      await pump(
        tester,
        tunnel: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: sentProperty,
          owners: const [marc],
          documents: [document('id', kind: DocumentKind.identityDocument)],
        ),
      );
      expect(find.text('Pièce reçue'), findsNWidgets(2));
    });

    testWidgets('without owners: any identity document', (tester) async {
      await pump(
        tester,
        tunnel: const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: sentProperty,
        ),
      );
      expect(find.text('À ajouter'), findsOneWidget);
    });

    testWidgets('nothing without a profile', (tester) async {
      when(() => profileCubit.state).thenReturn(const ProfileState());
      await pump(tester);
      expect(find.byType(ProfileView), findsNothing);
    });
  });
}

/// The page under the profile repository of the test.
class RepositoryProviderValue extends StatelessWidget {
  const new({required this.repository, super.key});

  final ProfileRepository repository;

  @override
  Widget build(BuildContext context) =>
      RepositoryProvider<ProfileRepository>.value(
        value: repository,
        child: const ProfilePage(),
      );
}
