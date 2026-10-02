import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mobileapp/ui/ui.dart';

import '../../../helpers/helpers.dart';

void main() {
  testWidgets('ListeningOrb renders every phase', (tester) async {
    for (final phase in VoicePhase.values) {
      await tester.pumpApp(ListeningOrb(phase: phase, level: 0.5, size: 95));
      expect(find.byType(RealestyIcon), findsOneWidget);
    }
  });

  testWidgets('VoiceWaveform shows 34 bars', (tester) async {
    await tester.pumpApp(const VoiceWaveform(levels: [0.2, 1]));
    expect(
      find.descendant(
        of: find.byType(VoiceWaveform),
        matching: find.byType(Container),
      ),
      findsNWidgets(VoiceConversationState.levelCount),
    );
  });

  testWidgets('labels of phases and errors', (tester) async {
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
      [for (final phase in VoicePhase.values) voicePhaseLabel(l10n, phase)],
      [
        '',
        'L’agent vous écoute…',
        'Je retranscris…',
        'L’agent réfléchit…',
        'L’agent vous répond…',
        'En pause',
        'J’ai tout ce qu’il me faut',
      ],
    );
    for (final error in VoiceError.values) {
      expect(voiceErrorLabel(l10n, error), isNotEmpty);
    }
  });

  testWidgets('FactPill, NightRoundButton and PauseGlyph', (tester) async {
    var taps = 0;
    await tester.pumpApp(
      Column(
        children: [
          FactPill(label: 'Construction 1998', onPressed: () => taps++),
          const FactPill(label: 'Assainissement ?', pending: true),
          NightRoundButton(
            semanticLabel: 'Pause',
            accent: true,
            onPressed: () => taps++,
            child: const PauseGlyph(color: Colors.black),
          ),
          NightRoundButton(
            semanticLabel: 'Clavier',
            onPressed: () => taps++,
            child: const SizedBox(),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Construction 1998'));
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.tap(find.bySemanticsLabel('Clavier'));
    expect(taps, 3);
    expect(find.text('Assainissement ?'), findsOneWidget);
  });
}
