import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _property = Property(
  id: 'p',
  ownerId: 'u',
  propertyType: PropertyType.house,
  livingAreaM2: 100,
  roomsCount: 1,
  bedroomsCount: 0,
  levels: PropertyLevels.singleStorey,
  heatingSystems: [HeatingSystem.gas],
);

const _year = PendingAnswer(
  id: 'a1',
  propertyId: 'p',
  targetStep: 'technical',
  kind: PendingKind.field,
  field: 'construction_year',
  value: 1998,
  label: 'Construction 1998',
  quote: 'elle date de 1998',
  sourceStep: 'context',
  turnId: 't0',
);

const _note = PendingAnswer(
  id: 'a2',
  propertyId: 'p',
  targetStep: 'technical',
  kind: PendingKind.note,
  value: 'Grenier aménageable',
  label: 'Note',
  quote: 'q',
  sourceStep: 'context',
);

/// EPIC-16 on V4b: the sheet opens by itself, the values said elsewhere
/// start « À confirmer », the notes and the origins are saved.
void main() {
  late VoiceSheetMocks mocks;

  setUp(() {
    VoiceFirstLauncher.resetSession();
    mocks = VoiceSheetMocks(
      turn: const AgentTurn(
        turnId: 't1',
        transcript: 'la toiture est de 2010',
        reply: 'Noté.',
        patch: {'roof_year': 2010},
        facts: [AgentPill(field: 'roof_year', label: 'Toiture 2010')],
        notes: ['Chaudière au garage'],
      ),
    );
  });
  tearDown(() => mocks.dispose());

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    VoiceInputMode mode = VoiceInputMode.voice,
    int currentStep = 1,
    List<PendingAnswer> pending = const [_year, _note],
  }) async {
    final view = tester.view
      ..physicalSize = const Size(390, 3600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(
      SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property.fromJson({
          ..._property.toJson(),
          'current_step': currentStep,
        }),
        pendingAnswers: pending,
      ),
    );
    await tester.pumpTunnelPage(
      RepositoryProvider.value(
        value: await mocks.services(inputMode: mode),
        child: const TechnicalPage(),
      ),
      sellerTunnelCubit: cubit,
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('opens the sheet by itself; pre-filled values « À confirmer »', (
    tester,
  ) async {
    final cubit = await pump(tester);
    expect(find.text('Audit technique à la voix'), findsOneWidget);
    expect(
      find.textContaining('J’ai déjà noté : Construction 1998, Note.'),
      findsOneWidget,
    );
    await mocks.speak(tester);
    await mocks.close(tester);
    expect(find.text('Audit technique à la voix'), findsNothing);
    expect(find.byType(ToConfirmTag), findsNWidgets(2));
    expect(find.text('1998'), findsOneWidget);
    expect(
      find.text('Grenier aménageable · Chaudière au garage'),
      findsOneWidget,
    );
    // The snackbar of the session goes away.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer et continuer'));
    await tester.pumpAndSettle();
    final patch = savedStepPatch(cubit, SellerTunnelStep.technical);
    expect(patch['construction_year'], 1998);
    expect(patch['roof_year'], 2010);
    expect(patch['step_notes'], {
      'technical': 'Grenier aménageable · Chaudière au garage',
    });
  });

  testWidgets('a validated step without pending answers stays on the form', (
    tester,
  ) async {
    await pump(tester, currentStep: 6, pending: const []);
    expect(find.text('Audit technique à la voix'), findsNothing);
    expect(find.byType(ToConfirmTag), findsNothing);
  });

  testWidgets('the written mode keeps the form; « Répondre à la voix »', (
    tester,
  ) async {
    await pump(tester, mode: VoiceInputMode.text);
    expect(find.text('Audit technique à la voix'), findsNothing);
    await tester.tap(find.text('Répondre à la voix'));
    await tester.pumpAndSettle();
    expect(find.text('Audit technique à la voix'), findsOneWidget);
    await mocks.close(tester);
  });
}
