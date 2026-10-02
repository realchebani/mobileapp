import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/ui/ui.dart';

import '../../helpers/helpers.dart';

void main() {
  group(AgentActionBar, () {
    testWidgets('shows the microphone when voice is available', (tester) async {
      final voice = await testVoiceServices();
      var mic = 0;
      await tester.pumpApp(
        RepositoryProvider.value(
          value: voice,
          child: AgentActionBar(
            hint: 'Répondez à la voix ou à l’écran',
            label: 'Continuer',
            onPressed: () {},
            onMicPressed: () => mic++,
          ),
        ),
      );
      expect(find.text('Répondez à la voix ou à l’écran'), findsOneWidget);
      await tester.tap(find.byType(RealestyMicButton));
      expect(mic, 1);
    });

    testWidgets('hides the microphone when voice is unavailable', (
      tester,
    ) async {
      await tester.pumpApp(
        AgentActionBar(
          label: 'Continuer',
          onPressed: () {},
          onMicPressed: () {},
        ),
      );
      expect(find.byType(RealestyMicButton), findsNothing);
    });

    testWidgets('shows the hint and the main action', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        AgentActionBar(
          hint: 'Les questions facultatives peuvent être passées',
          label: 'Continuer',
          onPressed: () => taps++,
        ),
      );

      expect(
        find.text('Les questions facultatives peuvent être passées'),
        findsOneWidget,
      );
      expect(find.byType(RealestyMicButton), findsNothing);
      await tester.tap(find.text('Continuer'));
      expect(taps, 1);
    });

    testWidgets('hides the voice hint without microphone', (tester) async {
      await tester.pumpApp(
        AgentActionBar(
          hint: 'Répondez à la voix ou à l’écran',
          label: 'Continuer',
          onPressed: () {},
        ),
      );
      expect(find.text('Répondez à la voix ou à l’écran'), findsNothing);

      await tester.pumpApp(
        AgentActionBar(
          hint: 'Répondez à la voix ou à l’écran',
          label: 'Continuer',
          onPressed: () {},
          showMic: true,
        ),
      );
      expect(find.text('Répondez à la voix ou à l’écran'), findsOneWidget);
    });

    testWidgets('shows the microphone and a loading action', (tester) async {
      var mic = 0;
      await tester.pumpApp(
        AgentActionBar(
          label: 'Envoyer',
          onPressed: () {},
          isLoading: true,
          variant: RealestyButtonVariant.accent,
          trailingIcon: RealestyIcons.chevronRight,
          showMic: true,
          onMicPressed: () => mic++,
        ),
      );

      final button = tester.widget<RealestyButton>(find.byType(RealestyButton));
      expect(button.isLoading, isTrue);
      expect(button.variant, RealestyButtonVariant.accent);
      expect(button.trailingIcon, RealestyIcons.chevronRight);
      expect(button.loadingSemanticLabel, 'chargement en cours');
      await tester.tap(find.bySemanticsLabel('Parler à l’agent'));
      expect(mic, 1);
    });
  });
}
