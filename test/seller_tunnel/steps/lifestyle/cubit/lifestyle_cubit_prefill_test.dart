import 'package:agent_repository/agent_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/lifestyle/cubit/lifestyle_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

PendingAnswer _pending(String id, String kind, String label) => PendingAnswer(
  id: id,
  propertyId: 'property-id',
  targetStep: 'lifestyle',
  kind: PendingKind.lifestyleItem,
  value: {'kind': kind, 'label': label},
  label: label,
  quote: 'q',
  sourceStep: 'context',
  turnId: 't0',
);

/// EPIC-16: items said on another step, origin of each label.
void main() {
  late MockPropertyRepository repository;
  final at = DateTime.utc(2026, 10, 2);

  setUpAll(
    () => registerFallbackValue(
      const LifestyleItem(
        propertyId: 'p',
        kind: LifestyleItemKind.asset,
        label: 'x',
      ),
    ),
  );

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.saveLifestyleItem(any())).thenAnswer(
      (invocation) async =>
          invocation.positionalArguments.single as LifestyleItem,
    );
    when(() => repository.deleteLifestyleItem(any())).thenAnswer((_) async {});
  });

  String? kind(LifestyleItem item) =>
      (item.fieldSources['label'] as Map?)?['s'] as String?;

  test('pending items join the lists and are resolved on submit', () async {
    var ids = 0;
    const saved = LifestyleItem(
      id: 'i0',
      propertyId: 'property-id',
      kind: LifestyleItemKind.asset,
      label: 'Calme',
      fieldSources: {
        'label': {'s': 'saisi', 'at': '2026-01-01T00:00:00Z'},
      },
    );
    final cubit = LifestyleCubit(
      propertyRepository: repository,
      property: const Property(id: 'property-id', ownerId: 'u'),
      items: const [saved],
      pendingItems: [
        _pending('kept', 'asset', 'École au bout de la rue'),
        _pending('edited', 'watch_point', 'Route passante'),
        _pending('removed', 'asset', 'Marché le samedi'),
        _pending('confirmed', 'asset', 'Parc à côté'),
        _pending('invalid', 'asset', 'x'),
      ],
      newId: () => 'n${ids++}',
      clock: () => at,
    );
    expect(cubit.state.assets.map((d) => d.pendingId), [
      null,
      'kept',
      'removed',
      'confirmed',
    ]);
    expect(cubit.state.watchPoints.single.pendingId, 'edited');
    cubit
      ..itemEdited(cubit.state.watchPoints.single, 'Route très passante')
      ..itemRemoved(cubit.state.assets[2])
      ..itemAdded(LifestyleItemKind.asset, 'Boulangerie');
    await cubit.submit(confirmed: {'confirmed'});
    expect(cubit.state.pendingResolutions, {
      PendingResolution.continueTapped: ['kept'],
      PendingResolution.modified: ['edited'],
      PendingResolution.erased: ['removed', 'invalid'],
      PendingResolution.yes: ['confirmed'],
    });
    final items = cubit.state.savedItems;
    expect(items.first, saved);
    verifyNever(() => repository.saveLifestyleItem(saved));
    expect(kind(items[1]), 'dicte_autre_etape');
    expect((items[2].fieldSources['label']! as Map)['c'], 'oui');
    expect(kind(items[3]), 'saisi'); // Boulangerie, typed
    expect(kind(items.last), 'saisi'); // the edited watch point
  });

  test('an item said here is traced to its turn', () async {
    final cubit = LifestyleCubit(
      propertyRepository: repository,
      property: const Property(id: 'property-id', ownerId: 'u'),
      newId: () => 'n',
      clock: () => at,
    );
    await cubit.voiceTurnApplied(
      const AgentTurn(
        turnId: 't1#c2',
        transcript: '',
        reply: '',
        lifestyleItems: [
          AgentLifestyleItem(isAsset: true, label: 'Vue dégagée'),
        ],
      ),
    );
    await cubit.submit();
    expect(cubit.state.savedItems.single.fieldSources['label'], {
      's': 'dicte',
      't': 't1',
      'k': 'c2.li:0',
      'at': '2026-10-02T00:00:00.000Z',
    });
  });
}
