import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:realesty_backoffice/app/router/routes.dart';
import 'package:realesty_backoffice/app/session/session_cubit.dart';

const Set<String> _gates = {
  BoRoutes.loading,
  BoRoutes.login,
  BoRoutes.mfa,
  BoRoutes.denied,
  BoRoutes.failed,
};

/// Every navigation rule: the session decides the screen; admin pages
/// need their capability.
String? appRedirect(SessionState session, String location) {
  String? gate(String path) => location == path ? null : path;
  switch (session.status) {
    case SessionStatus.unknown:
      return gate(BoRoutes.loading);
    case SessionStatus.signedOut:
      return gate(BoRoutes.login);
    case SessionStatus.mfa:
      return gate(BoRoutes.mfa);
    case SessionStatus.denied:
      return gate(BoRoutes.denied);
    case SessionStatus.failed:
      return gate(BoRoutes.failed);
    case SessionStatus.ready:
      final me = session.me!;
      if (_gates.contains(location) || location == '/') return BoRoutes.queue;
      if (location.startsWith(BoRoutes.team) &&
          !me.can(BackOfficeCapability.team)) {
        return BoRoutes.queue;
      }
      if (location.startsWith(BoRoutes.audit) &&
          !me.can(BackOfficeCapability.auditAll)) {
        return BoRoutes.queue;
      }
      return null;
  }
}
