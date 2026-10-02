import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/cubit/property_context_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _answered = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
  purchaseYear: 2012,
  selfBuilt: false,
);

PendingAnswer _pending(String id, Map<String, Object?> values) => PendingAnswer(
  id: id,
  propertyId: 'property-id',
  targetStep: 'context',
  kind: PendingKind.previousEstimate,
  value: values,
  label: id,
  quote: 'q',
  sourceStep: 'technical',
  turnId: 't0',
);

/// EPIC-16: estimates said on another step, origins of the cards.
void main() {
  late MockPropertyRepository repository;
  final at = DateTime.utc(2026, 10, 2);

  setUpAll(
    () => registerFallbackValue(
      const PreviousEstimate(propertyId: 'p', priceEur: 1),
    ),
  );

  setUp(() {
    repository = MockPropertyRepository();
    var next = 0;
    when(() => repository.savePreviousEstimate(any()))
        .thenAnswer((invocation) async {
          final estimate =
              invocation.positionalArguments.single as PreviousEstimate;
          return PreviousEstimate(
            id: estimate.id ?? 'saved-${next++}',
            propertyId: estimate.propertyId,
            priceEur: estimate.priceEur,
            estimatedMonth: estimate.estimatedMonth,
            agencyName: estimate.agencyName,
            source: estimate.source,
            fieldSources: estimate.fieldSources,
          );
        });
    when(() => repository.deletePreviousEstimate(any()))
        .thenAnswer((_) async {});
  });

  PropertyContextCubit build({
    List<PreviousEstimate> estimates = const [],
    List<PendingAnswer> pending = const [],
  }) => PropertyContextCubit(
    propertyRepository: repository,
    property: _answered,
    estimates: estimates,
    pendingEstimates: pending,
    today: DateTime(2026, 10),
    clock: () => at,
  );

  String? kind(PreviousEstimate estimate, String column) =>
      (estimate.fieldSources[column] as Map?)?['s'] as String?;

  test('pending estimates start as cards and are resolved on submit', () async {
    final cubit = build(
      pending: [
        _pending('kept', {
          'price_eur': 300000,
          'estimated_month': '2025-03-01',
          'agency_name': 'Agence',
        }),
        _pending('changed', {'price_eur': 310000}),
        _pending('removed', {'price_eur': 320000}),
        _pending('confirmed', {'price_eur': 330000}),
      ],
    );
    expect(cubit.state.previouslyEstimated, isTrue);
    expect(cubit.state.estimates.map((d) => d.pendingId), [
      'kept',
      'changed',
      'removed',
      'confirmed',
    ]);
    expect(
      cubit.state.estimates.map((d) => d.price.replaceAll(RegExp(r'\D'), '')),
      ['300000', '310000', '320000', '330000'],
    );
    expect(cubit.state.estimates.first.month, '03/2025');
    final changed = cubit.state.estimates[1];
    cubit
      ..estimateChanged(changed.key, price: '311 000')
      ..estimateRemoved(cubit.state.estimates[2].key);
    await cubit.submit(confirmed: {'confirmed'});
    expect(cubit.state.submission, PropertyContextSubmission.success);
    expect(cubit.state.estimateResolutions, {
      PendingResolution.continueTapped: ['kept'],
      PendingResolution.modified: ['changed'],
      PendingResolution.erased: ['removed'],
      PendingResolution.yes: ['confirmed'],
    });
    final saved = cubit.state.savedEstimates;
    expect(saved.first.source, EstimateSource.voice);
    expect(kind(saved.first, 'price_eur'), 'dicte_autre_etape');
    expect(kind(saved.first, 'agency_name'), 'dicte_autre_etape');
    expect(kind(saved[1], 'price_eur'), 'saisi');
    expect(saved[1].source, EstimateSource.manual);
    expect((saved[2].fieldSources['price_eur']! as Map)['c'], 'oui');
  });

  test('an estimate dictated here is traced to its turn; an unchanged one '
      'is kept', () async {
    const stored = PreviousEstimate(
      id: 'e1',
      propertyId: 'property-id',
      priceEur: 200000,
      fieldSources: {
        'price_eur': {'s': 'saisi', 'at': '2026-01-01T00:00:00Z'},
      },
    );
    final cubit = build(
      estimates: [stored],
      pending: [
        _pending('p', {'price_eur': 250000}),
      ],
    );
    await cubit.voiceTurnApplied(
      const AgentTurn(
        turnId: 't1#c1',
        transcript: '',
        reply: '',
        entityOps: [
          AgentEntityChange(
            entity: AgentEntity.previousEstimate,
            op: AgentEntityOp.create,
            target: 'new',
            label: 'x',
            values: {'price_eur': 400000},
          ),
          AgentEntityChange(
            entity: AgentEntity.previousEstimate,
            op: AgentEntityOp.update,
            target: 'E2',
            label: 'x',
            values: {'price_eur': 260000},
          ),
        ],
      ),
    );
    await cubit.submit();
    final saved = cubit.state.savedEstimates;
    // Unchanged: not written again.
    expect(saved.first, stored);
    verifyNever(() => repository.savePreviousEstimate(stored));
    // The pending card said again by voice: replaced.
    expect(cubit.state.estimateResolutions, {
      PendingResolution.replaced: ['p'],
    });
    expect(saved[1].fieldSources['price_eur'], {
      's': 'dicte',
      't': 't1',
      'k': 'c1.op:1.price_eur',
      'at': '2026-10-02T00:00:00.000Z',
    });
    expect(saved.last.fieldSources['price_eur'], {
      's': 'dicte',
      't': 't1',
      'k': 'c1.op:0.price_eur',
      'at': '2026-10-02T00:00:00.000Z',
    });
  });
}
