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
import 'package:mobileapp/seller_space/seller_space.dart';
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
  final sellerNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'seller');
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
      // Seller space: the dossier is loaded once for every /vendeur screen
      // (SellerTunnelShell provides SellerTunnelCubit). Inside, the four
      // tabs (StatefulShellRoute, one navigation stack per tab); the tunnel
      // steps V1–V8 are pushed above the tabs, on the seller navigator.
      ShellRoute(
        navigatorKey: sellerNavigatorKey,
        builder: (context, state, child) => SellerTunnelShell(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                SellerTabScaffold(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.seller,
                    builder: (context, state) => const MyPropertyPage(),
                    routes: [
                      GoRoute(
                        path: _child(AppRoutes.sellerReport),
                        builder: (context, state) => const ReportPage(),
                      ),
                      // TODO(EPIC-05): V8b (/vendeur/marche) goes here, with
                      // parentNavigatorKey: sellerNavigatorKey. The dashboard
                      // shows its link once the route exists.
                      for (final (path, page) in _sellerTunnelPages)
                        GoRoute(
                          parentNavigatorKey: sellerNavigatorKey,
                          path: _child(path),
                          builder: (context, state) => page,
                        ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.sellerVisits,
                    builder: (context, state) => ComingSoonPage.visits(context),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.sellerVault,
                    builder: (context, state) => ComingSoonPage.vault(context),
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.sellerAccount,
                    builder: (context, state) =>
                        AccountPage(showDesignSystemLink: enableDesignSystem),
                  ),
                ],
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

/// [location] relative to the seller space root (`/vendeur/x` → `x`).
String _child(String location) =>
    location.substring(AppRoutes.seller.length + 1);

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
