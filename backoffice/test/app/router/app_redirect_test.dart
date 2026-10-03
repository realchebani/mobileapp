import 'package:flutter_test/flutter_test.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/app/router/app_redirect.dart';

import '../../helpers/helpers.dart';

void main() {
  group('appRedirect', () {
    test('gates follow the session', () {
      final cases = {
        SessionStatus.unknown: BoRoutes.loading,
        SessionStatus.signedOut: BoRoutes.login,
        SessionStatus.mfa: BoRoutes.mfa,
        SessionStatus.denied: BoRoutes.denied,
        SessionStatus.failed: BoRoutes.failed,
      };
      for (final MapEntry(key: status, value: path) in cases.entries) {
        final session = SessionState(status: status);
        expect(appRedirect(session, BoRoutes.queue), path);
        expect(appRedirect(session, path), isNull);
      }
    });

    test('a member leaves the gates for the queue', () {
      const admin = SessionState(status: SessionStatus.ready, me: adminMe);
      expect(appRedirect(admin, BoRoutes.login), BoRoutes.queue);
      expect(appRedirect(admin, '/'), BoRoutes.queue);
      expect(appRedirect(admin, BoRoutes.team), isNull);
      expect(appRedirect(admin, BoRoutes.audit), isNull);
      expect(appRedirect(admin, BoRoutes.dossier('p1', 'avis')), isNull);
    });

    test('team and journal are for admins', () {
      const expert = SessionState(status: SessionStatus.ready, me: expertMe);
      expect(appRedirect(expert, BoRoutes.team), BoRoutes.queue);
      expect(appRedirect(expert, BoRoutes.audit), BoRoutes.queue);
      expect(appRedirect(expert, BoRoutes.queue), isNull);
    });

    test('routes', () {
      expect(BoRoutes.dossier('p1'), '/dossiers/p1');
      expect(BoRoutes.dossier('p1', 'photos'), '/dossiers/p1/photos');
    });
  });
}
