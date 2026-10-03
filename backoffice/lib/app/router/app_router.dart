import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:realesty_backoffice/app/router/app_redirect.dart';
import 'package:realesty_backoffice/app/router/routes.dart';
import 'package:realesty_backoffice/app/session/session_cubit.dart';
import 'package:realesty_backoffice/app/view/gates.dart';
import 'package:realesty_backoffice/app/view/shell.dart';
import 'package:realesty_backoffice/audit/audit.dart';
import 'package:realesty_backoffice/dossier/dossier.dart';
import 'package:realesty_backoffice/login/login.dart';
import 'package:realesty_backoffice/mfa/mfa.dart';
import 'package:realesty_backoffice/queue/queue.dart';
import 'package:realesty_backoffice/team/team.dart';

/// Rebuilds the routes when the session changes.
class _SessionListenable extends ChangeNotifier {
  new(SessionCubit cubit) {
    _subscription = cubit.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<SessionState> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

GoRouter createRouter(SessionCubit session, {String initialLocation = '/'}) =>
    GoRouter(
      initialLocation: initialLocation,
      refreshListenable: _SessionListenable(session),
      redirect: (context, state) => appRedirect(session.state, state.uri.path),
      routes: [
        GoRoute(path: '/', redirect: (_, _) => BoRoutes.queue),
        GoRoute(path: BoRoutes.loading, builder: (_, _) => const LoadingGate()),
        GoRoute(path: BoRoutes.login, builder: (_, _) => const LoginPage()),
        GoRoute(path: BoRoutes.mfa, builder: (_, _) => const MfaPage()),
        GoRoute(path: BoRoutes.denied, builder: (_, _) => const DeniedGate()),
        GoRoute(path: BoRoutes.failed, builder: (_, _) => const FailedGate()),
        ShellRoute(
          builder: (context, state, child) =>
              BoShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: BoRoutes.queue,
              builder: (_, _) => const QueuePage(),
              routes: [
                GoRoute(
                  path: ':id',
                  redirect: (_, state) =>
                      state.uri.path ==
                          BoRoutes.dossier(state.pathParameters['id']!)
                      ? BoRoutes.dossier(
                          state.pathParameters['id']!,
                          DossierTab.synthesis.segment,
                        )
                      : null,
                  routes: [
                    GoRoute(
                      path: ':tab',
                      builder: (_, state) => DossierPage(
                        propertyId: state.pathParameters['id']!,
                        tab: DossierTab.fromSegment(
                          state.pathParameters['tab'],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(path: BoRoutes.team, builder: (_, _) => const TeamPage()),
            GoRoute(path: BoRoutes.audit, builder: (_, _) => const AuditPage()),
          ],
        ),
      ],
    );
