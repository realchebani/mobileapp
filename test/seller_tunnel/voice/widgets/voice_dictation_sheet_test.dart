import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockDictation extends MockCubit<VoiceDictationState>
    implements VoiceDictationCubit;

void main() {
  late _MockDictation dictation;

  setUp(() {
    dictation = _MockDictation();
    when(() => dictation.start()).thenAnswer((_) async {});
    when(() => dictation.finish()).thenAnswer((_) async {});
    when(() => dictation.cancel()).thenAnswer((_) async {});
  });

  Future<List<String?>> pump(
    WidgetTester tester,
    VoiceDictationState state, {
    Stream<VoiceDictationState>? states,
    VoiceServices services = const VoiceServices(),
  }) async {
    if (states != null) {
      whenListen(dictation, states, initialState: state);
    } else {
      when(() => dictation.state).thenReturn(state);
    }
    final results = <String?>[];
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              builder: (_) => RepositoryProvider.value(
                value: services,
                child: BlocProvider<VoiceDictationCubit>.value(
                  value: dictation,
                  child: const VoiceDictationSheet(
                    title: 'Dictez l’adresse',
                    hint: 'Dites le numéro',
                  ),
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('listening: hint, "J’ai fini", "Annuler"', (tester) async {
    final results = await pump(
      tester,
      const VoiceDictationState(phase: VoicePhase.listening),
    );
    expect(find.text('Dictez l’adresse'), findsOneWidget);
    expect(find.text('Dites le numéro'), findsOneWidget);
    await tester.tap(find.text('J’ai fini'));
    verify(() => dictation.finish()).called(1);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    verify(() => dictation.cancel()).called(1);
    expect(results, [null]);
  });

  testWidgets('« Écrire plutôt » cancels (EPIC-16)', (tester) async {
    final services = await testVoiceServices(inputMode: VoiceInputMode.voice);
    final results = await pump(
      tester,
      const VoiceDictationState(phase: VoicePhase.listening),
      services: services,
    );
    await tester.tap(find.text('Écrire plutôt'));
    await tester.pumpAndSettle();
    verify(() => dictation.cancel()).called(1);
    expect(results, [null]);
    expect(services.preferences!.inputMode, VoiceInputMode.text);
  });

  testWidgets('pops the text once transcribed', (tester) async {
    const listening = VoiceDictationState(phase: VoicePhase.listening);
    final results = await pump(
      tester,
      listening,
      states: Stream.value(
        const VoiceDictationState(phase: VoicePhase.done, text: '12 rue'),
      ),
    );
    await tester.pumpAndSettle();
    expect(results, ['12 rue']);
  });

  testWidgets('errors: retry, none for the quota', (tester) async {
    await pump(tester, const VoiceDictationState(error: VoiceError.network));
    expect(find.text('Je retranscris…'), findsNothing);
    await tester.tap(find.text('Réessayer'));
    verify(() => dictation.start()).called(1);
  });

  testWidgets('quota: no retry', (tester) async {
    await pump(tester, const VoiceDictationState(error: VoiceError.quota));
    expect(find.text('Réessayer'), findsNothing);
  });
}
