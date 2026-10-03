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

/// Every navigation rule: the session decides the screen (the page asked
/// first is kept in `?from=` and opened once signed in); admin pages need
/// their capability.
String? appRedirect(SessionState session, Uri uri) {
  final location = uri.path;
  String? gate(String path) {
    if (location == path) return null;
    final from = _gates.contains(location)
        ? uri.queryParameters['from']
        : (location == '/' ? null : uri.toString());
    return from == null
        ? path
        : Uri(path: path, queryParameters: {'from': from}).toString();
  }

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
      if (_gates.contains(location) || location == '/') {
        final from = uri.queryParameters['from'];
        // Only a page of this site (no « //host »), never a gate again.
        if (from == null ||
            !from.startsWith('/') ||
            from.startsWith('//') ||
            _gates.contains(Uri.parse(from).path)) {
          return BoRoutes.queue;
        }
        return appRedirect(session, Uri.parse(from)) ?? from;
      }
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
