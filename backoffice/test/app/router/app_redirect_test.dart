import 'package:flutter_test/flutter_test.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/app/router/app_redirect.dart';

import '../../helpers/helpers.dart';

void main() {
  group('appRedirect', () {
    test('gates follow the session and keep the page asked', () {
      final cases = {
        SessionStatus.unknown: BoRoutes.loading,
        SessionStatus.signedOut: BoRoutes.login,
        SessionStatus.mfa: BoRoutes.mfa,
        SessionStatus.denied: BoRoutes.denied,
        SessionStatus.failed: BoRoutes.failed,
      };
      for (final MapEntry(key: status, value: path) in cases.entries) {
        final session = SessionState(status: status);
        expect(
          appRedirect(session, Uri.parse('/dossiers/p1/avis')),
          '$path?from=%2Fdossiers%2Fp1%2Favis',
        );
        expect(appRedirect(session, Uri.parse('/')), path);
        expect(appRedirect(session, Uri.parse(path)), isNull);
      }
      expect(
        appRedirect(
          const SessionState(status: SessionStatus.mfa),
          Uri.parse('/connexion?from=%2Fjournal'),
        ),
        '/double-authentification?from=%2Fjournal',
      );
    });

    test('a member leaves the gates for the page asked or the queue', () {
      const admin = SessionState(status: SessionStatus.ready, me: adminMe);
      expect(appRedirect(admin, Uri.parse(BoRoutes.login)), BoRoutes.queue);
      expect(appRedirect(admin, Uri.parse('/')), BoRoutes.queue);
      expect(
        appRedirect(admin, Uri.parse('/chargement?from=%2Fdossiers%2Fp1')),
        '/dossiers/p1',
      );
      expect(
        appRedirect(admin, Uri.parse('/chargement?from=%2F%2Fevil.example')),
        BoRoutes.queue,
      );
      expect(
        appRedirect(admin, Uri.parse('/chargement?from=https%3A%2F%2Fx')),
        BoRoutes.queue,
      );
      expect(
        appRedirect(admin, Uri.parse('/chargement?from=%2Fconnexion')),
        BoRoutes.queue,
      );
      expect(appRedirect(admin, Uri.parse(BoRoutes.team)), isNull);
      expect(appRedirect(admin, Uri.parse(BoRoutes.audit)), isNull);
    });

    test('team and journal are for admins', () {
      const expert = SessionState(status: SessionStatus.ready, me: expertMe);
      expect(appRedirect(expert, Uri.parse(BoRoutes.team)), BoRoutes.queue);
      expect(appRedirect(expert, Uri.parse(BoRoutes.audit)), BoRoutes.queue);
      expect(
        appRedirect(expert, Uri.parse('/connexion?from=%2Fequipe')),
        BoRoutes.queue,
      );
      expect(appRedirect(expert, Uri.parse(BoRoutes.queue)), isNull);
    });

    test('routes', () {
      expect(BoRoutes.dossier('p1'), '/dossiers/p1');
      expect(BoRoutes.dossier('p1', 'photos'), '/dossiers/p1/photos');
    });
  });
}
