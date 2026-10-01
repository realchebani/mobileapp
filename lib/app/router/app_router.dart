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
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
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
      // Seller space: the dossier is loaded once for the entry screen and
      // every tunnel step (SellerTunnelShell provides SellerTunnelCubit).
      ShellRoute(
        builder: (context, state, child) => SellerTunnelShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.seller,
            builder: (context, state) =>
                SellerHomePage(showDesignSystemLink: enableDesignSystem),
            routes: [
              // V8b · Synthèse du marché (EPIC-05), opened from V8.
              GoRoute(
                path: AppRoutes.sellerMarket.substring(
                  AppRoutes.seller.length + 1,
                ),
                builder: (context, state) => const MarketSynthesisPage(),
              ),
              for (final (path, page) in _sellerTunnelPages)
                GoRoute(
                  path: path.substring(AppRoutes.seller.length + 1),
                  builder: (context, state) => page,
                ),
            ],
          ),
        ],
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

/// One screen per seller tunnel step; each page lives in its own file under
/// `lib/seller_tunnel/steps/`.
final List<(String, Widget)> _sellerTunnelPages = [
  (SellerTunnelStep.owners.path, const OwnersPage()),
  (SellerTunnelStep.location.path, const LocationPage()),
  (SellerTunnelStep.context.path, const PropertyContextPage()),
  (SellerTunnelStep.technical.path, const TechnicalPage()),
  (SellerTunnelStep.method.path, const MethodPage()),
  (SellerTunnelStep.surfaces.path, const SurfacesPage()),
  (SellerTunnelStep.lifestyle.path, const LifestylePage()),
  (SellerTunnelStep.documents.path, const DocumentsPage()),
  (SellerTunnelStep.submitted.path, const SubmittedPage()),
];
