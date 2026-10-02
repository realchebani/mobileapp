import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';

import '../../../helpers/helpers.dart';

void main() {
  group('ensureVoiceConsent', () {
    Future<bool?> run(
      WidgetTester tester,
      VoiceServices? services, {
      String? tap,
    }) async {
      bool? result;
      final button = Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await ensureVoiceConsent(context),
          child: const Text('go'),
        ),
      );
      await tester.pumpApp(
        services == null
            ? button
            : RepositoryProvider.value(value: services, child: button),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (tap != null) {
        await tester.ensureVisible(find.text(tap));
        await tester.tap(find.text(tap));
        await tester.pumpAndSettle();
      }
      return result;
    }

    testWidgets('false when voice is unavailable', (tester) async {
      expect(await run(tester, null), isFalse);
    });

    testWidgets('true when already given', (tester) async {
      expect(await run(tester, await testVoiceServices()), isTrue);
      expect(find.byType(VoiceConsentPage), findsNothing);
    });

    testWidgets('asks once and remembers an acceptance', (tester) async {
      final services = await testVoiceServices(consentGiven: false);
      expect(
        await run(tester, services, tap: 'J’accepte et j’active le micro'),
        isTrue,
      );
      expect(services.preferences!.consentGiven, isTrue);
    });

    testWidgets('a refusal keeps the screen mode', (tester) async {
      final services = await testVoiceServices(consentGiven: false);
      expect(await run(tester, services, tap: 'Continuer à l’écran'), isFalse);
      expect(services.preferences!.consentGiven, isFalse);
    });

    testWidgets('shows the providers and the retention', (tester) async {
      await tester.pumpApp(const VoiceConsentPage());
      expect(find.text('Répondre à la voix'), findsOneWidget);
      expect(find.textContaining('Whisper d’OpenAI'), findsOneWidget);
      expect(find.textContaining('jamais conservé'), findsOneWidget);
    });
  });
}
