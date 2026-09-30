import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/login/login.dart';

void main() {
  group('LoginFailureMessage', () {
    test('has a distinct French message for every reason', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('fr'));
      final messages = {
        for (final reason in LoginFailureReason.values) reason.message(l10n),
      };

      expect(messages, hasLength(LoginFailureReason.values.length));
      expect(
        LoginFailureReason.notAuthorized.message(l10n),
        'Cette adresse n’est pas autorisée pour le moment (version de test).',
      );
      expect(
        LoginFailureReason.linkExpired.message(l10n),
        'Ce lien a expiré ou a déjà été utilisé. Renvoyez-en un.',
      );
    });
  });
}
