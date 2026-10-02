import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  const ownerId = 'user-id';
  const house = Property(id: 'house', ownerId: ownerId);
  const garage = Property(
    id: 'garage',
    ownerId: ownerId,
    propertyType: PropertyType.parking,
  );
  const lot = PropertyLot(id: 'lot', ownerId: ownerId);
  const inLot = Property(id: 'garage', ownerId: ownerId, lotId: 'lot');
  const houseInLot = Property(id: 'house', ownerId: ownerId, lotId: 'lot');

  late PropertyRepository repository;

  setUpAll(() {
    registerFallbackValue(house);
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.listProperties(any()))
        .thenAnswer((_) async => [house, garage]);
    when(() => repository.listLots(any())).thenAnswer((_) async => []);
    when(() => repository.getParcels(any())).thenAnswer(
      (_) async => const [PropertyParcel(propertyId: 'x', idu: 'P1')],
    );
  });

  SellerPropertiesCubit build() => SellerPropertiesCubit(
    propertyRepository: repository,
    ownerId: ownerId,
    newId: () => 'new-id',
    timeout: const Duration(milliseconds: 50),
  );

  const loaded = SellerPropertiesState(
    status: SellerPropertiesStatus.success,
    properties: [house, garage],
  );

  group('load', () {
    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'lists the properties and lots',
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => const [
        SellerPropertiesState(status: SellerPropertiesStatus.loading),
        loaded,
      ],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'loads the parcels of the properties in a lot',
      setUp: () {
        when(() => repository.listProperties(any()))
            .thenAnswer((_) async => [house, inLot]);
        when(() => repository.listLots(any())).thenAnswer((_) async => [lot]);
      },
      build: build,
      act: (cubit) => cubit.load(),
      skip: 1,
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, inLot],
          lots: [lot],
          parcels: {
            'garage': {'P1'},
          },
        ),
      ],
      verify: (_) => verifyNever(() => repository.getParcels('house')),
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'creates the first property of a new seller',
      setUp: () {
        when(() => repository.listProperties(any()))
            .thenAnswer((_) async => []);
        when(() => repository.createProperty(id: 'new-id', ownerId: ownerId))
            .thenAnswer((_) async => house);
      },
      build: build,
      act: (cubit) => cubit.load(),
      skip: 1,
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house],
        ),
      ],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'fails, and ignores a load while loading',
      setUp: () =>
          when(() => repository.listProperties(any()))
              .thenAnswer((_) async => throw const PropertyLoadFailure()),
      build: build,
      act: (cubit) async {
        final first = cubit.load();
        await cubit.load();
        await first;
      },
      expect: () => const [
        SellerPropertiesState(status: SellerPropertiesStatus.loading),
        SellerPropertiesState(status: SellerPropertiesStatus.failure),
      ],
      errors: () => [isA<ParallelWaitError<Object?, Object?>>()],
    );

    test('ignores results and failures after close', () async {
      final completer = Completer<List<Property>>();
      when(() => repository.listProperties(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build();
      final loading = cubit.load();
      await cubit.close();
      completer.complete([house]);
      await loading;
      expect(cubit.state.status, SellerPropertiesStatus.loading);

      final failing = Completer<List<Property>>();
      when(() => repository.listProperties(any()))
          .thenAnswer((_) => failing.future);
      final other = build();
      final otherLoading = other.load();
      await other.close();
      failing.completeError(const PropertyLoadFailure());
      await otherLoading;
      expect(other.state.status, SellerPropertiesStatus.loading);
    });
  });

  group('refresh', () {
    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'reloads in the background',
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [house],
      ),
      act: (cubit) => cubit.refresh(),
      expect: () => const [loaded],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'keeps the list and rethrows on failure',
      setUp: () =>
          when(() => repository.listLots(any()))
              .thenAnswer((_) async => throw const PropertyLoadFailure()),
      build: build,
      seed: () => loaded,
      act: (cubit) async {
        await expectLater(cubit.refresh(), throwsA(isA<Object>()));
      },
      expect: () => const <SellerPropertiesState>[],
      errors: () => [isA<ParallelWaitError<Object?, Object?>>()],
    );

    test('ignores results and failures after close', () async {
      final completer = Completer<List<Property>>();
      when(() => repository.listProperties(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build();
      final refreshing = cubit.refresh();
      await cubit.close();
      completer.complete([house]);
      await refreshing;
      expect(cubit.state, const SellerPropertiesState());

      final failing = Completer<List<Property>>();
      when(() => repository.listProperties(any()))
          .thenAnswer((_) => failing.future);
      final other = build();
      final otherRefreshing = other.refresh();
      await other.close();
      failing.completeError(const PropertyLoadFailure());
      await expectLater(otherRefreshing, throwsA(isA<Object>()));
    });
  });

  group('propertyChanged', () {
    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'adds, replaces and ignores an unchanged property',
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit
        ..propertyChanged(garage)
        ..propertyChanged(inLot, lot: lot)
        ..propertyChanged(const Property(id: 'new', ownerId: ownerId))
        ..lotChanged(const PropertyLot(id: 'lot', ownerId: ownerId, name: 'L')),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, inLot],
          lots: [lot],
        ),
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [
            house,
            inLot,
            Property(id: 'new', ownerId: ownerId),
          ],
          lots: [lot],
        ),
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [
            house,
            inLot,
            Property(id: 'new', ownerId: ownerId),
          ],
          lots: [PropertyLot(id: 'lot', ownerId: ownerId, name: 'L')],
        ),
      ],
    );
  });

  group('deleteProperty', () {
    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'deletes the property and its emptied lot',
      setUp: () {
        when(() => repository.deleteProperty(any())).thenAnswer((_) async {});
        when(() => repository.deleteLot(any())).thenAnswer((_) async {});
      },
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [house, inLot],
        lots: [lot],
      ),
      act: (cubit) => cubit.deleteProperty(inLot),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house],
        ),
      ],
      verify: (_) => verify(() => repository.deleteLot('lot')).called(1),
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'keeps a lot that still has properties, and an undeletable one',
      setUp: () {
        when(() => repository.deleteProperty(any())).thenAnswer((_) async {});
        when(() => repository.deleteLot(any()))
            .thenAnswer((_) async => throw const LotFrozenFailure());
      },
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [
          houseInLot,
          inLot,
          Property(id: 'o', ownerId: ownerId),
        ],
        lots: [lot],
      ),
      act: (cubit) async {
        await cubit.deleteProperty(inLot);
        await cubit.deleteProperty(houseInLot);
      },
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [
            houseInLot,
            Property(id: 'o', ownerId: ownerId),
          ],
          lots: [lot],
        ),
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [Property(id: 'o', ownerId: ownerId)],
          lots: [lot],
        ),
      ],
      errors: () => [isA<LotFrozenFailure>()],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'rethrows a failure',
      setUp: () =>
          when(() => repository.deleteProperty(any()))
              .thenAnswer((_) async => throw const PropertyDeleteFailure()),
      build: build,
      seed: () => loaded,
      act: (cubit) async {
        await expectLater(
          cubit.deleteProperty(house),
          throwsA(isA<PropertyDeleteFailure>()),
        );
      },
      expect: () => const <SellerPropertiesState>[],
    );
  });

  group('lots', () {
    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'deleteLot frees its properties',
      setUp: () =>
          when(() => repository.deleteLot(any())).thenAnswer((_) async {}),
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [houseInLot, garage],
        lots: [lot],
      ),
      act: (cubit) => cubit.deleteLot('lot'),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, garage],
        ),
      ],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'createLot groups the properties, the first one as main',
      setUp: () {
        when(
          () => repository.createLot(
            id: 'lot',
            ownerId: ownerId,
            saleMode: LotSaleMode.togetherOrSeparately,
          ),
        ).thenAnswer((_) async => lot);
        when(() => repository.setPropertyLot('house', 'lot'))
            .thenAnswer((_) async => houseInLot);
        when(() => repository.updateLot('lot', any())).thenAnswer(
          (_) async => const PropertyLot(
            id: 'lot',
            ownerId: ownerId,
            mainPropertyId: 'house',
          ),
        );
      },
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit.createLot(
        lotId: 'lot',
        members: const [house, inLot],
        saleMode: LotSaleMode.togetherOrSeparately,
      ),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [houseInLot, inLot],
          lots: [
            PropertyLot(id: 'lot', ownerId: ownerId, mainPropertyId: 'house'),
          ],
          parcels: {
            'house': {'P1'},
            'garage': {'P1'},
          },
        ),
      ],
      verify: (_) =>
          verifyNever(() => repository.setPropertyLot('garage', any())),
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'createLot keeps the main property of an existing lot',
      setUp: () {
        when(() => repository.createLot(id: 'lot', ownerId: ownerId))
            .thenAnswer(
              (_) async => const PropertyLot(
                id: 'lot',
                ownerId: ownerId,
                mainPropertyId: 'garage',
              ),
            );
      },
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit.createLot(lotId: 'lot', members: const [inLot]),
      verify: (_) => verifyNever(() => repository.updateLot(any(), any())),
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'setLot moves a property and clears a main property that left',
      setUp: () {
        when(() => repository.setPropertyLot('house', null))
            .thenAnswer((_) async => house);
        when(() => repository.getParcels(any()))
            .thenAnswer((_) async => throw const PropertyLoadFailure());
      },
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [houseInLot, inLot],
        lots: [
          PropertyLot(id: 'lot', ownerId: ownerId, mainPropertyId: 'house'),
        ],
      ),
      act: (cubit) => cubit.setLot(houseInLot, null),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, inLot],
          lots: [
            PropertyLot(id: 'lot', ownerId: ownerId, mainPropertyId: 'house'),
          ],
        ),
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, inLot],
          lots: [PropertyLot(id: 'lot', ownerId: ownerId)],
        ),
      ],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'setLot into a lot loads the parcels of the property',
      setUp: () =>
          when(() => repository.setPropertyLot('garage', 'lot'))
              .thenAnswer((_) async => inLot),
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [house, garage],
        lots: [lot],
      ),
      act: (cubit) => cubit.setLot(garage, 'lot'),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, inLot],
          lots: [lot],
          parcels: {
            'garage': {'P1'},
          },
        ),
      ],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'setLot still records the property when its parcels fail',
      setUp: () {
        when(() => repository.setPropertyLot('garage', 'lot'))
            .thenAnswer((_) async => inLot);
        when(() => repository.getParcels(any()))
            .thenAnswer((_) async => throw const PropertyLoadFailure());
      },
      build: build,
      seed: () => const SellerPropertiesState(
        status: SellerPropertiesStatus.success,
        properties: [house, garage],
        lots: [lot],
      ),
      act: (cubit) => cubit.setLot(garage, 'lot'),
      expect: () => const [
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: [house, inLot],
          lots: [lot],
        ),
      ],
      errors: () => [isA<ParallelWaitError<Object?, Object?>>()],
    );

    blocTest<SellerPropertiesCubit, SellerPropertiesState>(
      'updateLot records the lot',
      setUp: () => when(() => repository.updateLot('lot', any())).thenAnswer(
        (_) async => const PropertyLot(id: 'lot', ownerId: ownerId, name: 'L'),
      ),
      build: build,
      seed: () => const SellerPropertiesState(lots: [lot]),
      act: (cubit) => cubit.updateLot('lot', {PropertyLotColumns.name: 'L'}),
      expect: () => const [
        SellerPropertiesState(
          lots: [PropertyLot(id: 'lot', ownerId: ownerId, name: 'L')],
        ),
      ],
    );

    test('ignores lot results after close', () async {
      when(() => repository.deleteLot(any())).thenAnswer((_) async {});
      when(() => repository.updateLot(any(), any()))
          .thenAnswer((_) async => lot);
      when(() => repository.setPropertyLot(any(), any()))
          .thenAnswer((_) async => inLot);
      when(() => repository.deleteProperty(any())).thenAnswer((_) async {});
      final cubit = build();
      await cubit.close();
      await cubit.deleteLot('lot');
      await cubit.updateLot('lot', const {});
      await cubit.setLot(garage, 'lot');
      await cubit.deleteProperty(house);
      expect(cubit.state, const SellerPropertiesState());
    });
  });

  group(SellerPropertiesState, () {
    test('finds properties, lots and members', () {
      const state = SellerPropertiesState(
        properties: [house, inLot],
        lots: [lot],
      );
      expect(state.propertyById('garage'), inLot);
      expect(state.propertyById('x'), isNull);
      expect(state.lotById('lot'), lot);
      expect(state.lotById(null), isNull);
      expect(state.membersOf('lot'), [inLot]);
      expect(state.standaloneProperties, [house]);
      expect(state.canAddProperty, isTrue);
      expect(
        SellerPropertiesState(
          properties: List.filled(PropertyRepository.maxProperties, house),
        ).canAddProperty,
        isFalse,
      );
    });
  });
}
