import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:profile_repository/profile_repository.dart';

void main() {
  ProfileState loaded([UserRole? role]) => ProfileState(
    status: ProfileStatus.success,
    profile: Profile(id: 'id', role: role),
  );

  String? redirect(
    String location, {
    AppStatus appStatus = AppStatus.unauthenticated,
    bool onboardingSeen = true,
    ProfileState profileState = const ProfileState(),
  }) => appRedirect(
    location: location,
    appStatus: appStatus,
    onboardingSeen: onboardingSeen,
    profileState: profileState,
  );

  group('appRedirect', () {
    group('while the session is restored', () {
      test('goes to the splash', () {
        expect(
          redirect(AppRoutes.login, appStatus: AppStatus.unknown),
          AppRoutes.splash,
        );
      });

      test('stays on the splash', () {
        expect(
          redirect(AppRoutes.splash, appStatus: AppStatus.unknown),
          isNull,
        );
      });
    });

    group('signed out', () {
      test('goes to the onboarding until it is seen', () {
        expect(
          redirect(AppRoutes.splash, onboardingSeen: false),
          AppRoutes.onboarding,
        );
        expect(
          redirect(AppRoutes.login, onboardingSeen: false),
          AppRoutes.onboarding,
        );
        expect(redirect(AppRoutes.onboarding, onboardingSeen: false), isNull);
      });

      test('allows the login screens once the onboarding is seen', () {
        expect(redirect(AppRoutes.login), isNull);
        expect(redirect(AppRoutes.loginEmail), isNull);
        expect(redirect(AppRoutes.checkInbox), isNull);
      });

      test('sends any other location to the login', () {
        expect(redirect(AppRoutes.splash), AppRoutes.login);
        expect(redirect(AppRoutes.onboarding), AppRoutes.login);
        expect(redirect(AppRoutes.role), AppRoutes.login);
        expect(redirect(AppRoutes.seller), AppRoutes.login);
        expect(redirect(AppRoutes.sellerOwners), AppRoutes.login);
        expect(redirect(AppRoutes.designSystem), AppRoutes.login);
        expect(redirect('/connexionx'), AppRoutes.login);
      });
    });

    group('signed in', () {
      String? signedIn(String location, ProfileState profileState) => redirect(
        location,
        appStatus: AppStatus.authenticated,
        profileState: profileState,
      );

      test('waits on the splash while the profile is not loaded', () {
        for (final status in [
          ProfileStatus.initial,
          ProfileStatus.loading,
          ProfileStatus.failure,
        ]) {
          final state = ProfileState(status: status);
          expect(signedIn(AppRoutes.checkInbox, state), AppRoutes.splash);
          expect(signedIn(AppRoutes.splash, state), isNull);
        }
      });

      test('goes to the role selector until a role is chosen', () {
        expect(signedIn(AppRoutes.splash, loaded()), AppRoutes.role);
        expect(signedIn(AppRoutes.role, loaded()), isNull);
      });

      test('goes to the space of the chosen role', () {
        expect(
          signedIn(AppRoutes.role, loaded(UserRole.seller)),
          AppRoutes.seller,
        );
        expect(signedIn(AppRoutes.seller, loaded(UserRole.seller)), isNull);
        expect(
          signedIn(AppRoutes.seller, loaded(UserRole.buyer)),
          AppRoutes.buyer,
        );
        expect(signedIn(AppRoutes.buyer, loaded(UserRole.buyer)), isNull);
      });

      test('allows the screens of the seller space to a seller', () {
        final seller = loaded(UserRole.seller);
        expect(signedIn(AppRoutes.sellerOwners, seller), isNull);
        expect(signedIn(AppRoutes.sellerSubmitted, seller), isNull);
        expect(signedIn('/vendeurx', seller), AppRoutes.seller);
        expect(signedIn(AppRoutes.sellerOwners, loaded()), AppRoutes.role);
        expect(signedIn('/role/x', loaded()), AppRoutes.role);
        expect(
          signedIn(AppRoutes.sellerOwners, loaded(UserRole.buyer)),
          AppRoutes.buyer,
        );
      });

      test('allows the design system gallery', () {
        expect(
          signedIn(AppRoutes.designSystem, loaded(UserRole.seller)),
          isNull,
        );
      });
    });
  });
}
