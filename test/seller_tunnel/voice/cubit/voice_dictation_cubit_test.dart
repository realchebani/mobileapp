import 'dart:async';
import 'dart:typed_data';

import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_repository/voice_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  late MockAgentRepository agent;
  late MockVoiceRecorder recorder;
  late StreamController<double> levels;
  late DateTime now;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
    registerFallbackValue(AgentStep.location);
  });

  void transcribe(Future<Transcription> Function() answer) => when(
    () => agent.transcribe(
      propertyId: any(named: 'propertyId'),
      step: any(named: 'step'),
      audio: any(named: 'audio'),
      duration: any(named: 'duration'),
      format: any(named: 'format'),
      dictation: any(named: 'dictation'),
    ),
  ).thenAnswer((_) => answer());

  setUp(() {
    agent = MockAgentRepository();
    recorder = MockVoiceRecorder();
    levels = StreamController<double>.broadcast();
    now = DateTime(2026, 10, 2);
    when(() => recorder.requestPermission()).thenAnswer((_) async => true);
    when(() => recorder.start()).thenAnswer((_) async {});
    when(() => recorder.levels()).thenAnswer((_) => levels.stream);
    when(() => recorder.cancel()).thenAnswer((_) async {});
    when(() => recorder.dispose()).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer(
      (_) async => RecordedAudio(
        bytes: Uint8List.fromList([1]),
        duration: const Duration(seconds: 2),
      ),
    );
    transcribe(
      () async => const Transcription(
        turnId: 't1',
        transcript: ' 12 rue des Lilas Lyon ',
      ),
    );
  });

  tearDown(() => levels.close());

  VoiceDictationCubit build() => VoiceDictationCubit(
    agentRepository: agent,
    recorder: recorder,
    propertyId: 'p1',
    step: AgentStep.location,
    clock: () => now,
  );

  Future<void> speak() async {
    levels.add(-20);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(milliseconds: 300));
    levels.add(-60);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(seconds: 2));
    levels.add(-60);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('listens, then transcribes only (dictation)', () async {
    final cubit = build();
    expect(cubit.state.level, 0);
    await cubit.start();
    expect(cubit.state.phase, VoicePhase.listening);
    for (var i = 0; i < 40; i++) {
      levels.add(-30);
    }
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.levels, hasLength(VoiceConversationState.levelCount));
    expect(cubit.state.level, 0.5);
    await speak();
    expect(cubit.state.phase, VoicePhase.done);
    expect(cubit.state.text, '12 rue des Lilas Lyon');
    verify(
      () => agent.transcribe(
        propertyId: 'p1',
        step: AgentStep.location,
        audio: any(named: 'audio'),
        duration: const Duration(seconds: 2),
        dictation: true,
      ),
    ).called(1);
    await cubit.finish(); // not listening any more
    await cubit.close();
    verify(() => recorder.dispose()).called(1);
  });

  test('failures', () async {
    final cubit = build();
    when(() => recorder.requestPermission()).thenAnswer((_) async => false);
    await cubit.start();
    expect(cubit.state.error, VoiceError.permissionDenied);
    when(() => recorder.requestPermission()).thenAnswer((_) async => true);
    when(() => recorder.start()).thenThrow(Exception('busy'));
    await cubit.start();
    expect(cubit.state.error, VoiceError.permissionDenied);
    when(() => recorder.start()).thenAnswer((_) async {});
    await cubit.start();
    expect(cubit.state.error, isNull);
    await cubit.finish(); // nothing heard
    expect(cubit.state.error, VoiceError.empty);
    for (final (failure, error) in [
      (const AgentLockedFailure(), VoiceError.locked),
      (const AgentQuotaFailure(), VoiceError.quota),
      (const AgentEmptyFailure(), VoiceError.empty),
      (const AgentTooLongFailure(), VoiceError.tooLong),
      (Exception('x'), VoiceError.network),
    ]) {
      transcribe(() async => throw failure);
      await cubit.start();
      await speak();
      expect(cubit.state.error, error);
    }
    await cubit.start();
    await cubit.cancel();
    verify(() => recorder.cancel()).called(1);
    await cubit.close();
  });

  test('a late transcription after closing is ignored', () async {
    final answer = Completer<Transcription>();
    transcribe(() => answer.future);
    final cubit = build();
    await cubit.start();
    unawaited(speak());
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    answer.complete(const Transcription(turnId: 't', transcript: 'x'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.text, isNull);
  });

  test('state', () {
    const state = VoiceDictationState(text: 'x');
    expect(state.copyWith(text: () => null).text, isNull);
    expect(state.copyWith(error: () => VoiceError.empty).text, 'x');
    expect(state.props, hasLength(4));
  });
}
