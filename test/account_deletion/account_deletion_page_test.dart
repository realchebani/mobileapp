import 'package:auth_repository/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/account_deletion/account_deletion.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mocktail/mocktail.dart';
import 'package:profile_repository/profile_repository.dart';

import '../helpers/helpers.dart';

void main() {
  late MockProfileRepository profiles;
  late MockAuthRepository auth;
  late MockProfileCubit profileCubit;
  late MockGoRouter router;

  setUpAll(loadRealestyFonts);

  setUp(() {
    profiles = MockProfileRepository();
    auth = MockAuthRepository();
    when(() => auth.linkFailures).thenAnswer((_) => const Stream.empty());
    when(() => auth.signOut(everywhere: true)).thenAnswer((_) async {});
    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(
      const ProfileState(
        status: ProfileStatus.success,
        profile: Profile(id: 'user-id', role: UserRole.seller),
      ),
    );
    router = MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
    when(() => router.canPop()).thenReturn(false);
  });

  Future<void> pump(WidgetTester tester) async {
    usePhoneSurface();
    tester.view.physicalSize = const Size(390, 1400);
    await tester.pumpApp(
      const AccountDeletionPage(),
      profileRepository: profiles,
      authRepository: auth,
      profileCubit: profileCubit,
      goRouter: router,
    );
    await tester.pumpAndSettle();
  }

  group(AccountDeletionPage, () {
    testWidgets('deactivates the account after the confirmation', (
      tester,
    ) async {
      when(profiles.getDeletionBlockers).thenAnswer((_) async => {});
      when(profiles.deactivateAccount)
          .thenAnswer((_) async => DateTime(2026, 11, 2));
      await pump(tester);
      expect(find.text('Supprimer mon compte'), findsNWidgets(2));
      expect(find.textContaining('30 jours'), findsOneWidget);
      await tester.tap(find.text('Supprimer mon compte').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Saisissez « SUPPRIMER » pour confirmer.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'supprimer');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Compte désactivé'), findsOneWidget);
      expect(find.textContaining('02/11/2026'), findsOneWidget);
      await tester.tap(find.text('Terminer'));
      await tester.pumpAndSettle();
      verify(() => auth.signOut(everywhere: true)).called(1);
      await tester.tap(find.bySemanticsLabel('Retour'));
      await tester.pumpAndSettle();
      verify(() => auth.signOut(everywhere: true)).called(1);
    });

    testWidgets('explains an active sale', (tester) async {
      when(profiles.getDeletionBlockers)
          .thenAnswer((_) async => {AccountDeletionBlocker.activeSale});
      await pump(tester);
      expect(
        find.textContaining('Un de vos biens est en vente'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retirer mon bien de la vente'));
      verify(() => router.go(AppRoutes.seller)).called(1);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => router.go(AppRoutes.sellerAccount)).called(1);
    });

    testWidgets('a team account; back to the buyer space', (tester) async {
      when(profiles.getDeletionBlockers)
          .thenAnswer((_) async => {AccountDeletionBlocker.staffAccount});
      when(() => profileCubit.state).thenReturn(
        const ProfileState(
          status: ProfileStatus.success,
          profile: Profile(id: 'user-id', role: UserRole.buyer),
        ),
      );
      await pump(tester);
      expect(find.textContaining('équipe Realesty'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => router.go(AppRoutes.buyer)).called(1);
    });

    testWidgets('a failed check, then a failed deactivation', (tester) async {
      when(profiles.getDeletionBlockers)
          .thenThrow(const AccountDeletionFailure());
      when(() => profileCubit.state).thenReturn(
        const ProfileState(
          status: ProfileStatus.success,
          profile: Profile(id: 'user-id'),
        ),
      );
      await pump(tester);
      expect(
        find.text('Impossible de vérifier votre compte pour l’instant.'),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => router.go(AppRoutes.role)).called(1);
      when(profiles.getDeletionBlockers).thenAnswer((_) async => {});
      when(profiles.deactivateAccount)
          .thenThrow(const AccountDeletionFailure());
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'SUPPRIMER');
      await tester.tap(find.text('Supprimer mon compte').last);
      await tester.pumpAndSettle();
      expect(
        find.text('Votre compte n’a pas pu être désactivé. Réessayez.'),
        findsOneWidget,
      );
    });
  });

  group(AccountDeactivatedPage, () {
    late MockAppBloc appBloc;

    setUp(() {
      appBloc = MockAppBloc();
      when(() => appBloc.state)
          .thenReturn(const AppState.authenticated(AuthUser(id: 'user-id')));
      when(() => profileCubit.state).thenReturn(
        ProfileState(
          status: ProfileStatus.success,
          profile: Profile(
            id: 'user-id',
            deactivatedAt: DateTime(2026, 10, 3),
            deletionDueAt: DateTime(2026, 11, 2),
          ),
        ),
      );
    });

    Future<void> pumpDeactivated(WidgetTester tester) async {
      usePhoneSurface();
      tester.view.physicalSize = const Size(390, 1200);
      await tester.pumpApp(
        const AccountDeactivatedPage(),
        profileRepository: profiles,
        profileCubit: profileCubit,
        appBloc: appBloc,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('reactivates the account', (tester) async {
      when(profiles.reactivateAccount).thenAnswer((_) async {});
      await pumpDeactivated(tester);
      expect(find.text('Votre compte est désactivé'), findsOneWidget);
      expect(find.textContaining('02/11/2026'), findsOneWidget);
      await tester.tap(find.text('Réactiver mon compte'));
      await tester.pump();
      verify(() => profileCubit.profileUpdated(const Profile(id: 'user-id')))
          .called(1);
    });

    testWidgets('a failed reactivation; signs out', (tester) async {
      when(profiles.reactivateAccount)
          .thenThrow(const AccountDeletionFailure());
      await pumpDeactivated(tester);
      await tester.tap(find.text('Réactiver mon compte'));
      await tester.pumpAndSettle();
      expect(
        find.text('Votre compte n’a pas pu être réactivé. Réessayez.'),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 10));
      await tester.tap(find.text('Se déconnecter'));
      verify(() => appBloc.add(const AppLogoutPressed())).called(1);
    });

    testWidgets('without a date nor a profile', (tester) async {
      when(() => profileCubit.state).thenReturn(const ProfileState());
      await pumpDeactivated(tester);
      expect(
        find.text('Vous avez demandé la suppression de votre compte.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Réactiver mon compte'));
      await tester.pumpAndSettle();
      verifyNever(profiles.reactivateAccount);
    });
  });
}
