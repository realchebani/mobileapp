import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_voice_sheet.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/helpers.dart';

class _MockConversation extends MockCubit<VoiceConversationState>
    implements VoiceConversationCubit;

void main() {
  late _MockConversation conversation;

  setUp(() {
    conversation = _MockConversation();
    for (final call in <Future<void> Function()>[
      conversation.stop,
      conversation.retry,
      conversation.toggleMute,
      conversation.finishSpeaking,
    ]) {
      when(call).thenAnswer((_) async {});
    }
  });

  final urls = <Uri>[];

  Future<void> pump(WidgetTester tester, VoiceConversationState state) async {
    when(() => conversation.state).thenReturn(state);
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
                  child: const LifestyleVoiceSheet(),
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
    verify(conversation.stop).called(1);
    expect(find.byType(LifestyleVoiceSheet), findsNothing);
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
}
