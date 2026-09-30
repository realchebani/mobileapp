import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/bloc/app_bloc.dart';
import 'package:mobileapp/app/data/onboarding_repository.dart';
import 'package:mobileapp/app/router/app_redirect.dart';
import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/home/home.dart';
import 'package:mobileapp/login/login.dart';
import 'package:mobileapp/onboarding/onboarding.dart';
import 'package:mobileapp/profile/profile.dart';
import 'package:mobileapp/role/role.dart';
import 'package:mobileapp/splash/splash.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:profile_repository/profile_repository.dart';

/// Builds the app router. Navigation follows [appRedirect], re-evaluated
/// whenever [refreshListenable] notifies (app and profile changes).
///
/// The design system gallery only exists when [enableDesignSystem] is set
/// (development flavor).
GoRouter createAppRouter({
  required AppBloc appBloc,
  required ProfileCubit profileCubit,
  required OnboardingRepository onboardingRepository,
  required Listenable refreshListenable,
  required bool enableDesignSystem,
}) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshListenable,
    redirect: (context, state) => appRedirect(
      location: state.matchedLocation,
      appStatus: appBloc.state.status,
      onboardingSeen: onboardingRepository.seen,
      profileState: profileCubit.state,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
        routes: [
          GoRoute(
            path: 'email',
            builder: (context, state) => const LoginEmailPage(),
          ),
          GoRoute(
            path: 'verifier',
            builder: (context, state) => const CheckInboxPage(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.role,
        builder: (context, state) => const RolePage(),
      ),
      GoRoute(
        path: AppRoutes.seller,
        builder: (context, state) => HomePlaceholderPage(
          role: UserRole.seller,
          showDesignSystemLink: enableDesignSystem,
        ),
      ),
      GoRoute(
        path: AppRoutes.buyer,
        builder: (context, state) => HomePlaceholderPage(
          role: UserRole.buyer,
          showDesignSystemLink: enableDesignSystem,
        ),
      ),
      if (enableDesignSystem)
        GoRoute(
          path: AppRoutes.designSystem,
          builder: (context, state) => const DesignSystemGalleryPage(),
        ),
    ],
  );
}
