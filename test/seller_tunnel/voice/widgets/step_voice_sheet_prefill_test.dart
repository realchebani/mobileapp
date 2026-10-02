import 'package:agent_repository/agent_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/helpers.dart';

class _MockConversation extends MockCubit<VoiceConversationState>
    implements VoiceConversationCubit;

/// A form doing nothing.
class _Form implements VoiceForm {
  @override
  Future<void> voiceTurnApplied(AgentTurn turn) async {}

  @override
  void undoVoiceTurn(String turnId) {}

  @override
  void undoVoicePill(String turnId, String key) {}

  @override
  int get voiceTurnCount => 0;

  @override
  void undoVoiceTurnsFrom(int index) {}

  @override
  AgentTurnContext get voiceContext => const AgentTurnContext();

  @override
  bool confirmPrefilled() => false;
}

/// The tunnel's side: the context step is validated.
class _Sink implements VoicePendingSink {
  int recorded = 0;

  @override
  void pendingRecorded(List<AgentCrossStep> items, List<String> ids) =>
      recorded++;

  @override
  bool isStepValidated(AgentStep step) => step == AgentStep.context;

  @override
  Future<bool> acceptPendingUpdate(String id) async => true;

  @override
  Future<void> rejectPending(String id, {required bool cancelled}) async {}
}

const _year = AgentCrossStep(
  id: 'p1',
  targetStep: AgentStep.technical,
  kind: AgentCrossStepKind.field,
  label: 'Construction 1998',
  confidence: 0.6,
);
const _pill = VoiceCrossPill(turnId: 't1', item: _year);

/// EPIC-16: « Écrire plutôt », « Noté pour … », « Continuer à l’écrit »,
/// « À confirmer » and the sheet's intro.
void main() {
  late _MockConversation conversation;
  late VoiceServices services;

  setUpAll(() => registerFallbackValue(_pill));

  setUp(() async {
    conversation = _MockConversation();
    when(conversation.stop).thenAnswer((_) async {});
    when(() => conversation.undoCross(any())).thenReturn(null);
    services = await testVoiceServices(inputMode: VoiceInputMode.voice);
  });

  Future<void> pump(WidgetTester tester, VoiceConversationState state) async {
    final view = tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    when(() => conversation.state).thenReturn(state);
    await tester.pumpApp(
      RepositoryProvider.value(
        value: services,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => RepositoryProvider.value(
                value: services,
                child: BlocProvider<VoiceConversationCubit>.value(
                  value: conversation,
                  child: const StepVoiceSheet(title: 'Technique'),
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

  const listening = VoiceConversationState(
    phase: VoicePhase.listening,
    messages: [VoiceMessage(text: 'Bonjour', fromAgent: true)],
  );

  testWidgets('« Écrire plutôt » closes the sheet and remembers it', (
    tester,
  ) async {
    await pump(tester, listening);
    await tester.tap(find.text('Écrire plutôt'));
    await tester.pumpAndSettle();
    expect(find.text('Technique'), findsNothing);
    expect(services.preferences!.inputMode, VoiceInputMode.text);
  });

  testWidgets('« Noté pour … » pills and their cross', (tester) async {
    await pump(
      tester,
      const VoiceConversationState(
        phase: VoicePhase.listening,
        messages: [VoiceMessage(text: 'Bonjour', fromAgent: true)],
        crossStep: [_pill],
      ),
    );
    expect(
      find.text('Noté pour Technique · Construction 1998 ?'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Annuler Construction 1998'));
    verify(() => conversation.undoCross(_pill)).called(1);
  });

  testWidgets('« Continuer à l’écrit » after turns understood nothing', (
    tester,
  ) async {
    await pump(
      tester,
      const VoiceConversationState(
        phase: VoicePhase.listening,
        messages: [VoiceMessage(text: 'Bonjour', fromAgent: true)],
        suggestScreenMode: true,
      ),
    );
    await tester.tap(find.text('Continuer à l’écrit'));
    await tester.pumpAndSettle();
    expect(find.text('Technique'), findsNothing);
    // The preference is unchanged.
    expect(services.preferences!.inputMode, VoiceInputMode.voice);
  });

  testWidgets('labels of the steps and of the updates', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpApp(
      Builder(
        builder: (context) {
          l10n = context.l10n;
          return const SizedBox();
        },
      ),
    );
    expect(
      [for (final step in AgentStep.values) voiceStepLabel(l10n, step)],
      ['Adresse', 'Contexte', 'Technique', 'Pièces', 'Cadre de vie'],
    );
    expect(
      prefillUpdateLabel(
        l10n,
        const AgentCrossStep(
          id: 'p',
          targetStep: AgentStep.context,
          kind: AgentCrossStepKind.field,
          label: 'Achat 2012',
          changedLabel: 'Achat : 2010 → 2012',
        ),
      ),
      'Mettre à jour Contexte · Achat : 2010 → 2012 ?',
    );
    expect(
      prefillUpdateLabel(l10n, _year),
      'Ajouter à Technique · Construction 1998 ?',
    );
    expect(
      prefillNotedLabel(
        l10n,
        const AgentCrossStep(
          id: 'p',
          targetStep: AgentStep.rooms,
          kind: AgentCrossStepKind.room,
          label: 'Cuisine',
        ),
      ),
      'Noté pour Pièces · Cuisine',
    );
  });

  testWidgets('« À confirmer » shows the words said on a touch', (
    tester,
  ) async {
    await tester.pumpApp(
      const Column(
        children: [
          ToConfirmTag(quote: 'elle date de 1998'),
          ToConfirmTag(),
        ],
      ),
    );
    expect(find.text('À confirmer'), findsNWidgets(2));
    await tester.tap(find.text('À confirmer').first);
    await tester.pumpAndSettle();
    expect(find.text('« elle date de 1998 »'), findsOneWidget);
  });

  group('showStepVoiceSheet', () {
    late VoiceSheetMocks mocks;

    testWidgets('a value for a validated step asks its update', (tester) async {
      final sink = _Sink();
      mocks.answer(
        const AgentTurn(
          turnId: 't1',
          transcript: 'x',
          reply: 'Noté.',
          crossStep: [
            AgentCrossStep(
              id: 'p1',
              targetStep: AgentStep.context,
              kind: AgentCrossStepKind.field,
              label: 'Achat 2012',
            ),
          ],
        ),
      );
      final voice = await mocks.services(inputMode: VoiceInputMode.voice);
      await tester.pumpApp(
        RepositoryProvider.value(
          value: voice,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStepVoiceSheet(
                  context,
                  propertyId: 'p',
                  step: AgentStep.technical,
                  form: _Form(),
                  title: 'Technique',
                  intro: 'Parlons technique',
                  pendingSink: sink,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await mocks.speak(tester);
      expect(
        find.text('Ajouter à Contexte · Achat 2012\u00a0?'),
        findsOneWidget,
      );
      expect(sink.recorded, 1);
      await mocks.close(tester);
    });

    setUp(() => mocks = VoiceSheetMocks());
    tearDown(() => mocks.dispose());

    Future<VoiceServices> open(
      WidgetTester tester, {
      bool consentGiven = true,
      bool autoOpened = false,
    }) async {
      final voice = await mocks.services(
        consentGiven: consentGiven,
        inputMode: VoiceInputMode.voice,
      );
      await tester.pumpApp(
        RepositoryProvider.value(
          value: voice,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showStepVoiceSheet(
                  context,
                  propertyId: 'p',
                  step: AgentStep.technical,
                  form: _Form(),
                  title: 'Technique',
                  intro: 'Parlons technique',
                  prefilledLabels: const ['Construction 1998', 'Gaz'],
                  autoOpened: autoOpened,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return voice;
    }

    testWidgets('the intro lists the values to confirm', (tester) async {
      await open(tester);
      expect(
        find.text(
          'J’ai déjà noté : Construction 1998, Gaz. C’est bien ça ? '
          'Dites oui, ou corrigez.',
        ),
        findsOneWidget,
      );
      await mocks.close(tester);
    });

    testWidgets('opened by itself, a refused consent means writing', (
      tester,
    ) async {
      final voice = await open(tester, consentGiven: false, autoOpened: true);
      await tester.tap(find.text('Continuer à l’écran'));
      await tester.pumpAndSettle();
      expect(voice.preferences!.inputMode, VoiceInputMode.text);
    });

    testWidgets('opened by the microphone, a refused consent changes nothing', (
      tester,
    ) async {
      final voice = await open(tester, consentGiven: false);
      await tester.tap(find.text('Continuer à l’écran'));
      await tester.pumpAndSettle();
      expect(voice.preferences!.inputMode, VoiceInputMode.voice);
    });
  });

  group('showVoiceDictationSheet', () {
    testWidgets('opened by itself, a refused consent means writing', (
      tester,
    ) async {
      final mocks = VoiceSheetMocks();
      addTearDown(mocks.dispose);
      final voice = await mocks.services(
        consentGiven: false,
        inputMode: VoiceInputMode.voice,
      );
      for (final autoOpened in [false, true]) {
        await tester.pumpApp(
          RepositoryProvider.value(
            value: voice,
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showVoiceDictationSheet(
                    context,
                    propertyId: 'p',
                    step: AgentStep.location,
                    title: 'Adresse',
                    hint: 'Dites l’adresse',
                    autoOpened: autoOpened,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continuer à l’écran'));
        await tester.pumpAndSettle();
        expect(
          voice.preferences!.inputMode,
          autoOpened ? VoiceInputMode.text : VoiceInputMode.voice,
        );
      }
    });
  });
}
