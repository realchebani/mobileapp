import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/helpers.dart';

void main() {
  group(VoicePreferences, () {
    test('remembers the consent and the muted voice', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = VoicePreferences(
        preferences: await SharedPreferences.getInstance(),
      );
      expect(preferences.consentGiven, isFalse);
      expect(preferences.agentMuted, isFalse);
      await preferences.giveConsent();
      await preferences.setAgentMuted(muted: true);
      expect(preferences.consentGiven, isTrue);
      expect(preferences.agentMuted, isTrue);
    });
  });

  group(VoiceServices, () {
    test('is available only when enabled with every service', () async {
      expect(const VoiceServices().isAvailable, isFalse);
      expect(VoiceServices.flagEnabled, isFalse);
      final services = await testVoiceServices();
      expect(services.isAvailable, isTrue);
      expect(
        VoiceServices(
          agentRepository: services.agentRepository,
          createRecorder: services.createRecorder,
          createPlayer: services.createPlayer,
          preferences: services.preferences,
        ).isAvailable,
        isFalse,
      );
    });

    testWidgets('of: provided or disabled', (tester) async {
      final services = await testVoiceServices();
      late VoiceServices found;
      late VoiceServices missing;
      await tester.pumpWidget(
        Column(
          children: [
            RepositoryProvider.value(
              value: services,
              child: Builder(
                builder: (context) {
                  found = VoiceServices.of(context);
                  return const SizedBox();
                },
              ),
            ),
            Builder(
              builder: (context) {
                missing = VoiceServices.of(context);
                return const SizedBox();
              },
            ),
          ],
        ),
      );
      expect(found, same(services));
      expect(missing.isAvailable, isFalse);
    });
  });
}
