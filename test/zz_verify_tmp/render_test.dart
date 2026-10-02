import 'package:agent_repository/agent_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/widgets/lifestyle_voice_sheet.dart';
import 'package:mobileapp/seller_tunnel/voice/voice.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

class _MockConversation extends MockCubit<VoiceConversationState>
    implements VoiceConversationCubit;

const _out =
    '/private/tmp/claude-501/-Users-maximececillon-dev-mobileapp/b5b65bb5-7560-4425-b602-9879cb3e49e3/scratchpad/verify-epic06/png';

const _house = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
);

Widget _scaled(double scale, Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

void main() {
  setUpAll(loadRealestyFonts);

  const conv = VoiceConversationState(
    phase: VoicePhase.listening,
    levels: [0.1, 0.3, 0.6, 0.8, 0.4, 0.2, 0.5, 0.7, 0.9, 0.3],
    messages: [
      VoiceMessage(
        text:
            'Bonjour ! Décrivez-moi votre bien : année de construction, surfaces, matériaux, toiture, chauffage… Je remplis le dossier au fur et à mesure.',
        fromAgent: true,
      ),
      VoiceMessage(
        text: 'Elle date de 1998, en parpaing, toiture en tuiles refaite en 2016.',
        fromAgent: false,
      ),
      VoiceMessage(
        text: 'Parfait. Et pour l’assainissement : tout-à-l’égout ou fosse septique ?',
        fromAgent: true,
      ),
    ],
    facts: [
      AgentPill(field: 'construction_year', label: 'Construction 1998'),
      AgentPill(field: 'wall_material', label: 'Parpaing'),
      AgentPill(field: 'roof_type', label: 'Toiture tuiles'),
    ],
    pending: [AgentPill(field: 'sanitation', label: 'Assainissement ?')],
  );

  for (final scale in [1.0, 1.3]) {
    for (final h in [844.0, 1500.0]) {
      testWidgets('V4 $scale $h', (tester) async {
        final view = tester.view
          ..physicalSize = Size(390, h)
          ..devicePixelRatio = 1;
        addTearDown(view.reset);
        final c = _MockConversation();
        when(() => c.state).thenReturn(conv);
        when(c.start).thenAnswer((_) async {});
        final services = await testVoiceServices();
        final tunnel = mockSellerTunnelCubit(
          const SellerTunnelState(
            status: SellerTunnelStatus.success,
            property: _house,
          ),
        );
        await tester.pumpTunnelPage(
          _scaled(
            scale,
            RepositoryProvider.value(
              value: services,
              child: BlocProvider<VoiceConversationCubit>.value(
                value: c,
                child: VoiceAuditView(documentPicker: _MockDocumentPicker()),
              ),
            ),
          ),
          sellerTunnelCubit: tunnel,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await expectLater(
          find.byType(VoiceAuditView),
          matchesGoldenFile(Uri.file('$_out/v4_${scale}_${h.toInt()}.png')),
        );
      });
    }

    testWidgets('consent $scale', (tester) async {
      usePhoneSurface();
      await tester.pumpApp(_scaled(scale, const VoiceConsentPage()));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(VoiceConsentPage),
        matchesGoldenFile(Uri.file('$_out/consent_$scale.png')),
      );
    });

    testWidgets('V6 sheet $scale', (tester) async {
      usePhoneSurface();
      final c = _MockConversation();
      when(() => c.state).thenReturn(
        VoiceConversationState(
          phase: VoicePhase.listening,
          levels: conv.levels,
          messages: const [
            VoiceMessage(
              text:
                  'Parlez-moi du quartier : commerces, écoles, transports, calme, voisinage… Je classe vos réponses en atouts et points de vigilance.',
              fromAgent: true,
            ),
            VoiceMessage(
              text: 'Il y a une boulangerie à deux minutes et l’école à pied, mais la rue est un peu bruyante le matin.',
              fromAgent: false,
            ),
            VoiceMessage(
              text: 'J’ai noté 2 atouts et 1 point de vigilance.',
              fromAgent: true,
            ),
          ],
        ),
      );
      await tester.pumpApp(
        _scaled(
          scale,
          Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.bottomCenter,
                child: Material(
                  color: const Color(0xFF0F1713),
                  child: BlocProvider<VoiceConversationCubit>.value(
                    value: c,
                    child: const LifestyleVoiceSheet(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(Uri.file('$_out/v6sheet_$scale.png')),
      );
    });
  }
}
