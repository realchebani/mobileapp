import 'package:mobileapp/app/bloc/app_bloc.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:profile_repository/profile_repository.dart';

/// Where to send the user who is going to [location], or `null` to let
/// them through.
///
/// - Session being restored → splash.
/// - Signed out → onboarding until it was seen, then the login screens.
/// - Signed in → splash while the profile loads (or failed to), then the
///   role selector until a role is chosen, then the space of that role
///   (any screen under it, e.g. `/vendeur/audit/...`).
///   The design system gallery stays reachable once the profile is loaded.
String? appRedirect({
  required String location,
  required AppStatus appStatus,
  required bool onboardingSeen,
  required ProfileState profileState,
}) {
  final String target;
  switch (appStatus) {
    case AppStatus.unknown:
      target = AppRoutes.splash;
    case AppStatus.unauthenticated:
      if (!onboardingSeen) {
        target = AppRoutes.onboarding;
      } else if (_isLoginRoute(location)) {
        return null;
      } else {
        target = AppRoutes.login;
      }
    case AppStatus.authenticated:
      if (profileState.status != ProfileStatus.success) {
        target = AppRoutes.splash;
      } else if (location == AppRoutes.designSystem) {
        return null;
      } else {
        target = switch (profileState.profile?.role) {
          null => AppRoutes.role,
          UserRole.seller => AppRoutes.seller,
          UserRole.buyer => AppRoutes.buyer,
        };
        // The screens of a space (e.g. the seller tunnel) live under it.
        if (target != AppRoutes.role && _isWithin(location, target)) {
          return null;
        }
      }
  }
  return location == target ? null : target;
}

bool _isWithin(String location, String root) =>
    location == root || location.startsWith('$root/');

bool _isLoginRoute(String location) => _isWithin(location, AppRoutes.login);
