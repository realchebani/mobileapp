import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

/// EPIC-16: the pending answers kept by the tunnel cubit.
void main() {
  const property = Property(
    id: 'property-id',
    ownerId: 'user-id',
    currentStep: 4,
    propertyType: PropertyType.house,
    constructionYear: 1998,
    purchasePriceEur: 300000,
    stepNotes: {'context': 'Vendu meublé'},
  );
  final at = DateTime.utc(2026, 10, 2);

  PendingAnswer answer(
    String id, {
    String target = 'technical',
    PendingKind kind = PendingKind.field,
    String? field,
    Object? value,
  }) => PendingAnswer(
    id: id,
    propertyId: 'property-id',
    targetStep: target,
    kind: kind,
    field: field,
    value: value,
    label: id,
    quote: 'q',
    sourceStep: 'location',
    turnId: 't1',
  );

  late PropertyRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(PendingResolution.yes);
  });

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.getProperty(any())).thenAnswer((_) async => property);
    when(() => repository.getOwners(any())).thenAnswer((_) async => []);
    when(() => repository.getParcels(any())).thenAnswer((_) async => []);
    when(() => repository.getPreviousEstimates(any()))
        .thenAnswer((_) async => []);
    when(() => repository.getRooms(any())).thenAnswer((_) async => []);
    when(() => repository.getLifestyleItems(any())).thenAnswer((_) async => []);
    when(() => repository.getDocuments(any())).thenAnswer((_) async => []);
    when(() => repository.resolvePendingAnswers(any(), any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.first as List<String>,
    );
    when(() => repository.updateProperty(any(), any()))
        .thenAnswer((_) async => property);
  });

  SellerTunnelCubit build() => SellerTunnelCubit(
    propertyRepository: repository,
    propertyId: 'property-id',
    timeout: const Duration(seconds: 1),
    clock: () => at,
  );

  test('loads the pending answers and settles those already saved', () async {
    when(() => repository.getPendingAnswers(any())).thenAnswer(
      (_) async => [
        answer('saved', field: 'construction_year', value: 1998),
        answer('open', field: 'roof_year', value: 2010),
        // Not asked for this type: hidden.
        answer('hidden', field: 'units_count', value: 4),
        answer(
          'room',
          target: 'rooms',
          kind: PendingKind.room,
          value: const {},
        ),
      ],
    );
    final cubit = build();
    await cubit.load();
    expect(cubit.state.pendingAnswers.map((a) => a.id), [
      'open',
      'hidden',
      'room',
    ]);
    expect(cubit.state.visiblePending.map((a) => a.id), ['open', 'room']);
    expect(
      cubit.state.pendingFor(SellerTunnelStep.technical).map((a) => a.id),
      ['open'],
    );
    expect(cubit.state.pendingFor(SellerTunnelStep.method).map((a) => a.id), [
      'room',
    ]);
    expect(cubit.state.pendingFor(SellerTunnelStep.owners), isEmpty);
    verify(
      () => repository.resolvePendingAnswers([
        'saved',
      ], PendingResolution.continueTapped),
    ).called(1);
    // Reloaded in the background too.
    await cubit.refresh();
    verify(() => repository.getPendingAnswers('property-id')).called(2);
  });

  test('a failure to load or resolve them never blocks the tunnel', () async {
    when(() => repository.getPendingAnswers(any())).thenThrow(Exception('x'));
    final cubit = build();
    await cubit.load();
    expect(cubit.state.status, SellerTunnelStatus.success);
    expect(cubit.state.pendingAnswers, isEmpty);
    when(() => repository.getPendingAnswers(any())).thenAnswer(
      (_) async => [answer('open', field: 'roof_year', value: 2010)],
    );
    await cubit.refresh();
    when(() => repository.resolvePendingAnswers(any(), any()))
        .thenThrow(Exception('x'));
    await cubit.resolvePending({
      PendingResolution.no: ['open'],
      PendingResolution.yes: [],
    });
    expect(cubit.state.pendingAnswers, isEmpty);
    await cubit.resolvePending(const {});
  });

  test('a sent dossier has no pending answers to load', () async {
    when(() => repository.getProperty(any())).thenAnswer(
      (_) async => const Property(
        id: 'property-id',
        ownerId: 'u',
        status: PropertyStatus.submitted,
      ),
    );
    await build().load();
    verifyNever(() => repository.getPendingAnswers(any()));
  });

  test('records the answers of a voice turn', () async {
    when(
      () => repository.getPendingAnswers(any()),
    ).thenAnswer((_) async => [answer('old', field: 'roof_year', value: 2010)]);
    final cubit = build()..pendingRecorded(const [], const []);
    expect(cubit.state.pendingAnswers, isEmpty);
    await cubit.load();
    cubit
      ..pendingRecorded(const [], const [])
      ..pendingRecorded(
        const [
          AgentCrossStep(
            id: 'new',
            targetStep: AgentStep.technical,
            kind: AgentCrossStepKind.field,
            field: 'roof_year',
            value: 2011,
            label: 'Toiture 2011',
            confidence: 0.6,
          ),
          AgentCrossStep(
            id: 'r',
            targetStep: AgentStep.rooms,
            kind: AgentCrossStepKind.room,
            label: 'Cuisine',
          ),
          AgentCrossStep(
            id: 'e',
            targetStep: AgentStep.context,
            kind: AgentCrossStepKind.previousEstimate,
            label: 'Estimation',
          ),
          AgentCrossStep(
            id: 'l',
            targetStep: AgentStep.lifestyle,
            kind: AgentCrossStepKind.lifestyleItem,
            label: 'Calme',
          ),
          AgentCrossStep(
            id: 'n',
            targetStep: AgentStep.location,
            kind: AgentCrossStepKind.note,
            label: 'Note',
          ),
        ],
        const ['old'],
      );
    expect(cubit.state.pendingAnswers.map((a) => (a.id, a.kind)), [
      ('new', PendingKind.field),
      ('r', PendingKind.room),
      ('e', PendingKind.previousEstimate),
      ('l', PendingKind.lifestyleItem),
      ('n', PendingKind.note),
    ]);
    expect(cubit.state.pendingAnswers.first.unsure, isTrue);
    expect(cubit.state.pendingAnswers.first.createdAt, at);
  });

  test('validated steps; an update said for one is saved on « oui »', () async {
    when(() => repository.getPendingAnswers(any())).thenAnswer(
      (_) async => [
        answer(
          'price',
          target: 'context',
          field: 'purchase_price_eur',
          value: 320000,
        ),
        answer(
          'note',
          target: 'context',
          kind: PendingKind.note,
          value: 'Cave',
        ),
        answer(
          'room',
          target: 'rooms',
          kind: PendingKind.room,
          value: const {},
        ),
      ],
    );
    final cubit = build();
    expect(cubit.state.isValidated(SellerTunnelStep.context), isFalse);
    expect(await cubit.acceptPendingUpdate('price'), isFalse);
    await cubit.load();
    expect(cubit.isStepValidated(AgentStep.context), isTrue);
    expect(cubit.isStepValidated(AgentStep.lifestyle), isFalse);
    expect(cubit.isStepValidated(AgentStep.rooms), isFalse);
    expect(await cubit.acceptPendingUpdate('price'), isTrue);
    final patch =
        verify(() => repository.updateProperty('property-id', captureAny()))
                .captured
                .single
            as Map<String, Object?>;
    expect(patch['purchase_price_eur'], 320000);
    expect(patch['provenance'], {'purchase_price_eur': 'declared'});
    expect((patch['field_sources']! as Map)['purchase_price_eur'], {
      's': 'dicte_autre_etape',
      't': 't1',
      'p': 'price',
      'c': 'mise_a_jour',
      'at': '2026-10-02T00:00:00.000Z',
    });
    verify(
      () => repository.resolvePendingAnswers(['price'], PendingResolution.yes),
    ).called(1);
    expect(await cubit.acceptPendingUpdate('note'), isTrue);
    final notes =
        verify(() => repository.updateProperty('property-id', captureAny()))
                .captured
                .single
            as Map<String, Object?>;
    expect(notes['step_notes'], {'context': 'Vendu meublé · Cave'});
    // An entity is never written from the sheet.
    expect(await cubit.acceptPendingUpdate('room'), isFalse);
    expect(await cubit.acceptPendingUpdate('unknown'), isFalse);
    // A failed save keeps it open.
    when(() => repository.getPendingAnswers(any())).thenAnswer(
      (_) async => [answer('long', kind: PendingKind.note, value: 'x' * 1200)],
    );
    await cubit.refresh();
    when(() => repository.updateProperty(any(), any()))
        .thenThrow(Exception('x'));
    expect(await cubit.acceptPendingUpdate('long'), isFalse);
    expect(cubit.state.pendingAnswers, hasLength(1));
  });

  test('a long note update is cut; « non » and the cross reject', () async {
    when(() => repository.getPendingAnswers(any())).thenAnswer(
      (_) async => [
        answer(
          'long',
          target: 'context',
          kind: PendingKind.note,
          value: 'x' * 1200,
        ),
        answer('a', field: 'roof_year', value: 2010),
        answer('b', field: 'sanitation', value: 'fosse'),
      ],
    );
    final cubit = build();
    await cubit.load();
    expect(await cubit.acceptPendingUpdate('long'), isTrue);
    final patch =
        verify(() => repository.updateProperty('property-id', captureAny()))
                .captured
                .single
            as Map<String, Object?>;
    expect(((patch['step_notes']! as Map)['context'] as String).length, 1000);
    await cubit.rejectPending('a', cancelled: false);
    await cubit.rejectPending('b', cancelled: true);
    verify(() => repository.resolvePendingAnswers(['a'], PendingResolution.no))
        .called(1);
    verify(
      () =>
          repository.resolvePendingAnswers(['b'], PendingResolution.cancelled),
    ).called(1);
  });

  test('saving a step resolves the answers it showed', () async {
    when(
      () => repository.getPendingAnswers(any()),
    ).thenAnswer((_) async => [answer('a', field: 'roof_year', value: 2010)]);
    final cubit = build();
    await cubit.load();
    await cubit.saveStepAndContinue(
      SellerTunnelStep.technical,
      const {'roof_year': 2010},
      resolve: {
        PendingResolution.continueTapped: ['a'],
      },
    );
    expect(cubit.state.nextStep, SellerTunnelStep.method);
    verify(
      () => repository.resolvePendingAnswers([
        'a',
      ], PendingResolution.continueTapped),
    ).called(1);
    await cubit.saveStep(const {'roof_year': 2010});
    // Nothing resolved after a failed save.
    when(() => repository.updateProperty(any(), any()))
        .thenThrow(Exception('x'));
    await cubit.saveStep(
      const {'roof_year': 2010},
      resolve: {
        PendingResolution.yes: ['b'],
      },
    );
    verifyNever(
      () => repository.resolvePendingAnswers(['b'], PendingResolution.yes),
    );
  });

  test('state helpers', () {
    expect(
      SellerTunnelState.pendingTargetOf(SellerTunnelStep.location),
      'location',
    );
    for (final step in [
      SellerTunnelStep.owners,
      SellerTunnelStep.documents,
      SellerTunnelStep.submitted,
    ]) {
      expect(SellerTunnelState.pendingTargetOf(step), isNull);
    }
    expect(
      SellerTunnelState.stepOfTarget('location'),
      SellerTunnelStep.location,
    );
    expect(SellerTunnelState.stepOfTarget('context'), SellerTunnelStep.context);
    expect(
      SellerTunnelState.stepOfTarget('technical'),
      SellerTunnelStep.technical,
    );
    expect(SellerTunnelState.stepOfTarget('rooms'), SellerTunnelStep.surfaces);
    expect(
      SellerTunnelState.stepOfTarget('lifestyle'),
      SellerTunnelStep.lifestyle,
    );
    expect(const SellerTunnelState().visiblePending, isEmpty);
    expect(
      const SellerTunnelState().isValidated(SellerTunnelStep.context),
      isFalse,
    );
  });
}
