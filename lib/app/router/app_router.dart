import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/account_deletion/account_deletion.dart';
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
      // Seller space: the seller's properties are loaded once for every
      // /vendeur screen (SellerTunnelShell); each screen of a property
      // (/vendeur/biens/<id>/…) gets the dossier of that property
      // (PropertyRouteScope). Inside, the four tabs (StatefulShellRoute, one
      // navigation stack per tab); the tunnel steps V1–V8, V8b and "Ajouter
      // un bien" are pushed above the tabs, on the seller navigator.
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
                        parentNavigatorKey: sellerNavigatorKey,
                        path: _child(AppRoutes.sellerNewProperty),
                        builder: (context, state) => const NewPropertyPage(),
                      ),
                      GoRoute(
                        path:
                            '${_child(AppRoutes.sellerProperties)}/'
                            ':$_propertyId',
                        builder: (context, state) => _property(
                          state,
                          const PropertyValuationScope(
                            child: PropertyHomePage(showBack: true),
                          ),
                        ),
                        routes: [
                          GoRoute(
                            path: 'rapport',
                            builder: (context, state) => _property(
                              state,
                              const PropertyValuationScope(child: ReportPage()),
                            ),
                          ),
                          // V8b · Synthèse du marché (EPIC-05), full screen
                          // above the tabs, opened from V8 and V9.
                          GoRoute(
                            parentNavigatorKey: sellerNavigatorKey,
                            path: 'marche',
                            builder: (context, state) =>
                                _property(state, const MarketSynthesisPage()),
                          ),
                          for (final (segment, page) in _sellerTunnelPages)
                            GoRoute(
                              parentNavigatorKey: sellerNavigatorKey,
                              path: '${AppRoutes.auditSegment}/$segment',
                              builder: (context, state) =>
                                  _property(state, page, auditSegment: segment),
                            ),
                        ],
                      ),
                      // Sales (EPIC-08), above the tabs.
                      ...saleRoutes(sellerNavigatorKey),
                      GoRoute(
                        path: '${_child(AppRoutes.sellerLots)}/:lotId',
                        builder: (context, state) =>
                            LotPage(lotId: state.pathParameters['lotId']!),
                      ),
                      // Links from before EPIC-13 (one property per seller).
                      GoRoute(
                        path: _child(AppRoutes.legacySellerReport),
                        builder: (context, state) =>
                            const LegacySellerRedirect(segments: ['rapport']),
                      ),
                      GoRoute(
                        path: _child(AppRoutes.legacySellerMarket),
                        builder: (context, state) =>
                            const LegacySellerRedirect(segments: ['marche']),
                      ),
                      GoRoute(
                        path: '${_child(AppRoutes.legacySellerAudit)}/:step',
                        builder: (context, state) => LegacySellerRedirect(
                          segments: [
                            AppRoutes.auditSegment,
                            state.pathParameters['step']!,
                          ],
                        ),
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
                  // C1 · Coffre-fort and V18 · Mes documents (EPIC-11).
                  GoRoute(
                    path: AppRoutes.sellerVault,
                    builder: (context, state) => const VaultPage(),
                    routes: [
                      GoRoute(
                        path: 'biens/:$_propertyId',
                        builder: (context, state) => VaultDocumentsPage(
                          target: VaultTarget.property(
                            state.pathParameters[_propertyId]!,
                          ),
                          rubric: VaultRubric.fromCode(
                            state.uri.queryParameters['rubrique'],
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'lots/:lotId',
                        builder: (context, state) => VaultDocumentsPage(
                          target: VaultTarget.lot(
                            state.pathParameters['lotId']!,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: AppRoutes.sellerAccount,
                    builder: (context, state) => FirstPropertyScope(
                      child: AccountPage(
                        showDesignSystemLink: enableDesignSystem,
                      ),
                    ),
                    // V19 and the notifications (EPIC-11), full screen.
                    routes: [
                      GoRoute(
                        parentNavigatorKey: sellerNavigatorKey,
                        path: 'profil',
                        builder: (context, state) =>
                            const FirstPropertyScope(child: ProfilePage()),
                      ),
                      GoRoute(
                        parentNavigatorKey: sellerNavigatorKey,
                        path: 'notifications',
                        builder: (context, state) => const NotificationsPage(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Account deletion (EPIC-11): from every space, and the screen of a
      // deactivated account.
      GoRoute(
        path: AppRoutes.accountDeletion,
        builder: (context, state) => const AccountDeletionPage(),
      ),
      GoRoute(
        path: AppRoutes.accountDeactivated,
        builder: (context, state) => const AccountDeactivatedPage(),
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

const _propertyId = 'propertyId';

/// [page] of the property of the route, under its dossier.
Widget _property(GoRouterState state, Widget page, {String? auditSegment}) =>
    PropertyRouteScope(
      propertyId: state.pathParameters[_propertyId]!,
      auditSegment: auditSegment,
      child: page,
    );

/// One screen per seller tunnel step (by path segment); each page lives in
/// its own file under `lib/seller_tunnel/steps/`.
final List<(String, Widget)> _sellerTunnelPages = [
  (SellerTunnelStep.owners.segment, const OwnersPage()),
  (SellerTunnelStep.location.segment, const LocationPage()),
  (SellerTunnelStep.context.segment, const PropertyContextPage()),
  (SellerTunnelStep.technical.segment, const TechnicalPage()),
  (SellerTunnelStep.voiceAuditSegment, const VoiceAuditPage()),
  (SellerTunnelStep.method.segment, const MethodPage()),
  (SellerTunnelStep.surfaces.segment, const SurfacesPage()),
  (SellerTunnelStep.lifestyle.segment, const LifestylePage()),
  (SellerTunnelStep.documents.segment, const DocumentsPage()),
  (SellerTunnelStep.submitted.segment, const SubmittedPage()),
];
