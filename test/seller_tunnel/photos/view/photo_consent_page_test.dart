import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/photos/photos.dart';

import '../../../helpers/helpers.dart';

void main() {
  group('ensurePhotoAnalysisConsent', () {
    Future<bool?> run(
      WidgetTester tester,
      PhotoServices? services, {
      bool ask = false,
      String? tap,
      bool dismiss = false,
    }) async {
      bool? result;
      final button = Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              result = await ensurePhotoAnalysisConsent(context, ask: ask),
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
      if (dismiss) {
        tester.state<NavigatorState>(find.byType(Navigator).last).pop();
        await tester.pumpAndSettle();
      }
      return result;
    }

    testWidgets('false without preferences', (tester) async {
      expect(await run(tester, null), isFalse);
      expect(find.byType(PhotoConsentPage), findsNothing);
    });

    testWidgets('true when already given', (tester) async {
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.given,
      );
      expect(await run(tester, services), isTrue);
      expect(find.byType(PhotoConsentPage), findsNothing);
    });

    testWidgets('a refusal is remembered and not asked again', (tester) async {
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
      );
      expect(await run(tester, services), isFalse);
      expect(find.byType(PhotoConsentPage), findsNothing);
    });

    testWidgets('asks again after a refusal when asked to', (tester) async {
      final services = await testPhotoServices(
        consent: PhotoAnalysisConsent.declined,
      );
      expect(
        await run(tester, services, ask: true, tap: 'J’accepte l’analyse'),
        isTrue,
      );
      expect(services.preferences!.consent, PhotoAnalysisConsent.given);
    });

    testWidgets('remembers a refusal', (tester) async {
      final services = await testPhotoServices();
      expect(await run(tester, services, tap: 'Continuer sans l’IA'), isFalse);
      expect(services.preferences!.consent, PhotoAnalysisConsent.declined);
    });

    testWidgets('a dismissed screen asks again next time', (tester) async {
      final services = await testPhotoServices();
      expect(await run(tester, services, dismiss: true), isFalse);
      expect(services.preferences!.consent, PhotoAnalysisConsent.unknown);
    });
  });

  testWidgets('PhotoConsentPage explains who sees the photos', (tester) async {
    usePhoneSurface();
    await tester.pumpApp(const PhotoConsentPage());
    expect(find.text('Analyse de vos photos par l’IA'), findsOneWidget);
    expect(find.textContaining('OpenRouter'), findsOneWidget);
    expect(find.text('Jamais de mesure'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('floutage'), 100);
    expect(find.textContaining('floutage'), findsOneWidget);
  });
}
