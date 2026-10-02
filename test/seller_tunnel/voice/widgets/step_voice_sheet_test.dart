import 'package:agent_repository/agent_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockConversation extends MockCubit<VoiceConversationState>
    implements VoiceConversationCubit;

const _confirmation = VoicePendingConfirmation(
  turnId: 't1',
  confirmation: AgentConfirmation(
    id: 'c1',
    reason: AgentConfirmationReason.typeChange,
    label: 'Type : garage ?',
  ),
);

const _pill = VoiceAppliedPill(
  turnId: 't1',
  key: 'purchase_year',
  label: 'Achat 2012',
  changedLabel: 'Modifié : 2010 → 2012',
);

void main() {
  late _MockConversation conversation;

  setUpAll(() {
    registerFallbackValue(_confirmation);
    registerFallbackValue(_pill);
  });

  setUp(() {
    conversation = _MockConversation();
    for (final call in <Future<void> Function()>[
      conversation.stop,
      conversation.retry,
      conversation.toggleMute,
      conversation.finishSpeaking,
      conversation.finish,
    ]) {
      when(call).thenAnswer((_) async {});
    }
    when(() => conversation.confirm(any())).thenAnswer((_) async {});
    when(() => conversation.reject(any())).thenAnswer((_) async {});
    when(() => conversation.undoPill(any())).thenReturn(null);
    when(() => conversation.undoTurn(any())).thenReturn(null);
  });

  final urls = <Uri>[];

  Future<void> pump(
    WidgetTester tester,
    VoiceConversationState state, {
    bool dictation = false,
    Widget? extra,
    Stream<VoiceConversationState>? states,
  }) async {
    final view = tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    if (states != null) {
      whenListen(conversation, states, initialState: state);
    } else {
      when(() => conversation.state).thenReturn(state);
    }
    final services = await testVoiceServices(openedUrls: urls);
    await tester.pumpApp(
      RepositoryProvider.value(
        value: services,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              // As in the app, the services sit above the sheet's route.
              builder: (_) => RepositoryProvider.value(
                value: services,
                child: BlocProvider<VoiceConversationCubit>.value(
                  value: conversation,
                  child: StepVoiceSheet(
                    title: 'Parlez librement',
                    dictation: dictation,
                    extra: extra,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('listening: last exchange, finish, mute, close', (tester) async {
    await pump(
      tester,
      const VoiceConversationState(
        phase: VoicePhase.listening,
        messages: [
          VoiceMessage(text: 'Parlez-moi du quartier', fromAgent: true),
          VoiceMessage(text: 'Très calme', fromAgent: false),
        ],
      ),
    );
    expect(find.text('Parlez librement'), findsOneWidget);
    expect(find.text('Très calme'), findsOneWidget);
    await tester.tap(find.text('J’ai fini'));
    verify(conversation.finishSpeaking).called(1);
    await tester.tap(find.text('Couper la voix de l’agent'));
    verify(conversation.toggleMute).called(1);
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    verify(conversation.finish).called(1);
  });

  testWidgets('pills: understood (undo), to confirm, pending, elsewhere', (
    tester,
  ) async {
    await pump(
      tester,
      const VoiceConversationState(
        phase: VoicePhase.listening,
        messages: [VoiceMessage(text: 'Bonjour', fromAgent: true)],
        applied: [_pill],
        confirmations: [_confirmation],
        pending: [AgentPill(field: 'sale_reason', label: 'Raison ?')],
        outOfStep: [
          AgentOutOfStep(
            field: 'construction_year',
            step: 'technical',
            label: 'Construction → Technique',
          ),
        ],
        turnIds: ['t1'],
      ),
      extra: const Text('extra'),
    );
    expect(find.text('Achat 2012 · Modifié : 2010 → 2012'), findsOneWidget);
    expect(find.text('Type : garage ?'), findsOneWidget);
    expect(find.text('Raison ?'), findsOneWidget);
    expect(find.text('Construction → Technique'), findsOneWidget);
    expect(find.text('extra'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Annuler Achat 2012'));
    verify(() => conversation.undoPill(_pill)).called(1);
    await tester.tap(find.text('Oui'));
    verify(() => conversation.confirm(_confirmation)).called(1);
    await tester.tap(find.text('Non'));
    verify(() => conversation.reject(_confirmation)).called(1);
    await tester.tap(find.text('Annuler ce tour'));
    verify(() => conversation.undoTurn('t1')).called(1);
  });

  testWidgets('errors: retry and settings', (tester) async {
    await pump(
      tester,
      const VoiceConversationState(
        muted: true,
        error: VoiceError.permissionDenied,
        messages: [VoiceMessage(text: 'Bonjour', fromAgent: true)],
      ),
    );
    expect(find.text('Réactiver la voix de l’agent'), findsOneWidget);
    await tester.tap(find.text('Réglages'));
    await tester.pump();
    expect(urls, [Uri.parse('app-settings:')]);
    await tester.tap(find.text('Réessayer'));
    verify(conversation.retry).called(1);
  });

  testWidgets('quota: no retry', (tester) async {
    await pump(
      tester,
      const VoiceConversationState(
        error: VoiceError.quota,
        messages: [VoiceMessage(text: 'Bonjour', fromAgent: true)],
      ),
    );
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('dictation: no voice toggle, a vibration per turn, closes '
      'when finished', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add('vibrate');
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const start = VoiceConversationState(
      phase: VoicePhase.listening,
      messages: [VoiceMessage(text: 'Dictez', fromAgent: true)],
    );
    await pump(
      tester,
      start,
      dictation: true,
      states: Stream.fromIterable([
        start.copyWith(turnIds: ['t1']),
        start.copyWith(turnIds: ['t1'], finished: true),
      ]),
    );
    expect(find.text('Couper la voix de l’agent'), findsNothing);
    await tester.pumpAndSettle();
    expect(haptics, ['vibrate']);
    expect(find.byType(StepVoiceSheet), findsNothing);
  });

  testWidgets('the "Dicté" tag', (tester) async {
    await tester.pumpApp(const DictatedTag());
    expect(find.text('Dicté'), findsOneWidget);
  });
}
