import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

void main() {
  final now = DateTime.utc(2026, 10, 2, 10);

  setUp(VoiceFirstLauncher.resetSession);

  Future<VoiceFirstSkip?> reason({
    VoiceInputMode mode = VoiceInputMode.voice,
    Map<String, Object> preferences = const {},
    bool hasVoice = true,
    bool locked = false,
    bool validated = false,
    bool hasPending = false,
    bool available = true,
  }) async {
    final services = available
        ? await testVoiceServices(
            inputMode: mode,
            extraPreferences: preferences,
          )
        : const VoiceServices();
    return VoiceFirstLauncher.skipReason(
      services: services,
      hasVoice: hasVoice,
      locked: locked,
      validated: validated,
      hasPending: hasPending,
      now: now,
    );
  }

  test('skipReason: every case', () async {
    expect(await reason(), isNull);
    expect(await reason(available: false), VoiceFirstSkip.unavailable);
    expect(await reason(hasVoice: false), VoiceFirstSkip.noVoice);
    expect(await reason(locked: true), VoiceFirstSkip.locked);
    expect(await reason(mode: VoiceInputMode.text), VoiceFirstSkip.textMode);
    expect(await reason(validated: true), VoiceFirstSkip.validated);
    // A validated step with something to confirm opens.
    expect(await reason(validated: true, hasPending: true), isNull);
    expect(
      await reason(preferences: {VoicePreferences.quotaDayKey: '2026-10-2'}),
      VoiceFirstSkip.quota,
    );
    expect(
      await reason(
        preferences: {
          VoicePreferences.offlineAtKey: now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        },
      ),
      VoiceFirstSkip.offline,
    );
    expect(
      await reason(preferences: {VoicePreferences.micDeniedKey: true}),
      VoiceFirstSkip.micDenied,
    );
  });

  Future<int> schedule(
    WidgetTester tester, {
    required VoiceServices services,
    bool locked = false,
  }) async {
    var opened = 0;
    await tester.pumpApp(
      RepositoryProvider.value(
        value: services,
        child: Scaffold(
          body: Builder(
            builder: (context) {
              VoiceFirstLauncher.schedule(
                context,
                hasVoice: true,
                locked: locked,
                validated: false,
                hasPending: false,
                open: () async => opened++,
                clock: () => now,
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('schedule opens the sheet after the first frame', (tester) async {
    final services = await testVoiceServices(inputMode: VoiceInputMode.voice);
    expect(await schedule(tester, services: services), 1);
  });

  testWidgets('schedule opens nothing when skipped', (tester) async {
    final services = await testVoiceServices(inputMode: VoiceInputMode.voice);
    expect(await schedule(tester, services: services, locked: true), 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a refused microphone shows its banner once per session, '
      'and is checked again when the app comes back', (tester) async {
    final opened = <Uri>[];
    final recorder = MockVoiceRecorder();
    var granted = false;
    when(recorder.requestPermission).thenAnswer((_) async => granted);
    when(recorder.dispose).thenAnswer((_) async {});
    final services = await testVoiceServices(
      inputMode: VoiceInputMode.voice,
      extraPreferences: {VoicePreferences.micDeniedKey: true},
      openedUrls: opened,
      recorder: recorder,
    );
    expect(await schedule(tester, services: services), 0);
    expect(
      find.text('Micro désactivé : vous pouvez répondre à l’écran.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Réglages'));
    await tester.pump();
    expect(opened, [Uri.parse('app-settings:')]);
    await tester.pumpWidget(const SizedBox());
    expect(await schedule(tester, services: services), 0);
    expect(
      find.text('Micro désactivé : vous pouvez répondre à l’écran.'),
      findsNothing,
    );
    // Allowed in the iOS Settings: cleared when the app comes back.
    granted = true;
    [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ].forEach(tester.binding.handleAppLifecycleStateChanged);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(services.preferences!.micDenied, isFalse);
    VoiceFirstLauncher.resetSession();
  });

  testWidgets('a microphone allowed since then opens the sheet', (
    tester,
  ) async {
    final recorder = MockVoiceRecorder();
    when(recorder.requestPermission).thenAnswer((_) async => true);
    when(recorder.dispose).thenAnswer((_) async {});
    final services = await testVoiceServices(
      inputMode: VoiceInputMode.voice,
      extraPreferences: {VoicePreferences.micDeniedKey: true},
      recorder: recorder,
    );
    expect(await schedule(tester, services: services), 1);
    expect(services.preferences!.micDenied, isFalse);
  });

  test('recheckMicrophone needs the services', () async {
    expect(
      await VoiceFirstLauncher.recheckMicrophone(const VoiceServices()),
      isFalse,
    );
  });
}
