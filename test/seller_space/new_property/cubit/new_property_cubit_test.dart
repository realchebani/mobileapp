import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/new_property/cubit/new_property_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  const ownerId = 'user-id';
  const house = Property(
    id: 'house',
    ownerId: ownerId,
    propertyType: PropertyType.house,
    ownershipType: OwnershipType.multiple,
  );
  const certified = Property(
    id: 'old',
    ownerId: ownerId,
    status: PropertyStatus.certified,
  );
  const created = Property(
    id: 'new-id',
    ownerId: ownerId,
    propertyType: PropertyType.parking,
  );
  const lot = PropertyLot(id: 'new-id', ownerId: ownerId);
  const identity = PropertyDocument(
    id: 'id-doc',
    propertyId: 'house',
    kind: DocumentKind.identityDocument,
    storagePath: 'user-id/house/id.pdf',
  );
  const owner = PropertyOwner(
    propertyId: 'new-id',
    position: 1,
    firstName: 'Marie',
    lastName: 'Durand',
  );

  late PropertyRepository repository;

  setUpAll(() {
    registerFallbackValue(identity);
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    repository = MockPropertyRepository();
    when(
      () => repository.createProperty(
        id: any(named: 'id'),
        ownerId: any(named: 'ownerId'),
        type: any(named: 'type'),
        lotId: any(named: 'lotId'),
      ),
    ).thenAnswer((_) async => created);
    when(
      () => repository.copyOwners(
        fromPropertyId: any(named: 'fromPropertyId'),
        toPropertyId: any(named: 'toPropertyId'),
      ),
    ).thenAnswer((_) async => [owner]);
    when(() => repository.updateProperty(any(), any()))
        .thenAnswer((_) async => created);
    when(() => repository.getDocuments(any())).thenAnswer(
      (_) async => [
        identity,
        const PropertyDocument(
          id: 'rejected',
          propertyId: 'house',
          kind: DocumentKind.identityDocument,
          storagePath: 'x',
          status: DocumentStatus.rejected,
        ),
        const PropertyDocument(
          id: 'deed',
          propertyId: 'house',
          kind: DocumentKind.titleDeed,
          storagePath: 'y',
        ),
      ],
    );
    when(
      () => repository.copyDocument(
        any(),
        ownerId: any(named: 'ownerId'),
        toPropertyId: any(named: 'toPropertyId'),
      ),
    ).thenAnswer((_) async => identity);
  });

  NewPropertyCubit build({List<Property> properties = const [house]}) =>
      NewPropertyCubit(
        propertyRepository: repository,
        ownerId: ownerId,
        properties: properties,
        newId: () => 'new-id',
      );

  group(NewPropertyState, () {
    test('partners, source and defaults', () {
      final state = build(properties: const [certified, house]).state;
      expect(state.partners, [house]);
      expect(state.source, house);
      expect(state.partner, isNull);
      expect(state.typeMissing, isTrue);
      expect(state.reuseOwners, isTrue);
      expect(state.copyWith(partnerId: () => 'house').source, house);
      expect(state.copyWith(sourceId: 'old').source, certified);
      expect(const NewPropertyState(properties: []).source, isNull);
    });
  });

  group(NewPropertyCubit, () {
    blocTest<NewPropertyCubit, NewPropertyState>(
      'edits the answers',
      build: build,
      act: (cubit) => cubit
        ..typeSelected(PropertyType.parking)
        ..partnerSelected('house')
        ..sourceSelected('house')
        ..reuseOwnersChanged(reuse: false)
        ..reuseIdentityChanged(reuse: false),
      verify: (cubit) {
        final state = cubit.state;
        expect(state.type, PropertyType.parking);
        expect(state.partnerId, 'house');
        expect(state.sourceId, 'house');
        expect(state.reuseOwners, isFalse);
        expect(state.reuseIdentity, isFalse);
      },
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'asks for the type first',
      build: build,
      act: (cubit) => cubit.submit(),
      expect: () => [
        isA<NewPropertyState>()
            .having((s) => s.showErrors, 'showErrors', isTrue)
            .having((s) => s.submitAttempts, 'submitAttempts', 1),
      ],
      verify: (_) => verifyNever(
        () => repository.createProperty(
          id: any(named: 'id'),
          ownerId: any(named: 'ownerId'),
        ),
      ),
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'creates the property and copies the owners and identity',
      build: build,
      seed: () => const NewPropertyState(
        properties: [house],
        type: PropertyType.parking,
      ),
      act: (cubit) => cubit.submit(),
      expect: () => [
        isA<NewPropertyState>().having(
          (s) => s.status,
          'status',
          NewPropertyStatus.inProgress,
        ),
        isA<NewPropertyState>()
            .having((s) => s.status, 'status', NewPropertyStatus.success)
            .having((s) => s.property, 'property', created)
            .having((s) => s.lot, 'lot', isNull),
      ],
      verify: (_) {
        verify(
          () => repository.createProperty(
            id: 'new-id',
            ownerId: ownerId,
            type: PropertyType.parking,
          ),
        ).called(1);
        verify(
          () => repository.copyOwners(
            fromPropertyId: 'house',
            toPropertyId: 'new-id',
          ),
        ).called(1);
        verify(
          () => repository.updateProperty('new-id', {
            PropertyColumns.ownershipType: OwnershipType.multiple,
            PropertyColumns.provenance: {Property.ownersCopiedFromKey: 'house'},
          }),
        ).called(1);
        verify(
          () => repository.copyDocument(
            identity,
            ownerId: ownerId,
            toPropertyId: 'new-id',
          ),
        ).called(1);
      },
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'creates a lot with the partner',
      setUp: () {
        when(() => repository.createLot(id: 'new-id', ownerId: ownerId))
            .thenAnswer((_) async => lot);
        when(() => repository.setPropertyLot('house', 'new-id'))
            .thenAnswer((_) async => house);
        when(() => repository.updateLot('new-id', any())).thenAnswer(
          (_) async => const PropertyLot(
            id: 'new-id',
            ownerId: ownerId,
            mainPropertyId: 'house',
          ),
        );
      },
      build: build,
      seed: () => const NewPropertyState(
        properties: [house],
        type: PropertyType.parking,
        partnerId: 'house',
        reuseOwners: false,
        reuseIdentity: false,
      ),
      act: (cubit) => cubit.submit(),
      skip: 1,
      expect: () => [
        isA<NewPropertyState>()
            .having((s) => s.status, 'status', NewPropertyStatus.success)
            .having((s) => s.lot?.mainPropertyId, 'main', 'house'),
      ],
      verify: (_) => verify(
        () => repository.createProperty(
          id: 'new-id',
          ownerId: ownerId,
          type: PropertyType.parking,
          lotId: 'new-id',
        ),
      ).called(1),
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'joins the lot of the partner',
      setUp: () => when(() => repository.listLots(ownerId)).thenAnswer(
        (_) async => const [
          PropertyLot(id: 'other', ownerId: ownerId),
          PropertyLot(id: 'lot', ownerId: ownerId, mainPropertyId: 'house'),
        ],
      ),
      build: () => build(
        properties: const [
          Property(id: 'house', ownerId: ownerId, lotId: 'lot'),
        ],
      ),
      seed: () => const NewPropertyState(
        properties: [Property(id: 'house', ownerId: ownerId, lotId: 'lot')],
        type: PropertyType.parking,
        partnerId: 'house',
        reuseOwners: false,
        reuseIdentity: false,
      ),
      act: (cubit) => cubit.submit(),
      verify: (cubit) {
        expect(cubit.state.lot?.id, 'lot');
        verifyNever(
          () => repository.createLot(
            id: any(named: 'id'),
            ownerId: any(named: 'ownerId'),
          ),
        );
      },
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'creates a lot when the lot of the partner is gone',
      setUp: () {
        when(() => repository.listLots(ownerId)).thenAnswer((_) async => []);
        when(() => repository.createLot(id: 'new-id', ownerId: ownerId))
            .thenAnswer(
              (_) async => const PropertyLot(
                id: 'new-id',
                ownerId: ownerId,
                mainPropertyId: 'house',
              ),
            );
        when(() => repository.setPropertyLot('house', 'new-id'))
            .thenAnswer((_) async => house);
      },
      build: build,
      seed: () => const NewPropertyState(
        properties: [Property(id: 'house', ownerId: ownerId, lotId: 'gone')],
        type: PropertyType.parking,
        partnerId: 'house',
        reuseOwners: false,
        reuseIdentity: false,
      ),
      act: (cubit) => cubit.submit(),
      verify: (cubit) {
        expect(cubit.state.status, NewPropertyStatus.success);
        verifyNever(() => repository.updateLot(any(), any()));
      },
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'reports the limit',
      setUp: () => when(
        () => repository.createProperty(
          id: any(named: 'id'),
          ownerId: any(named: 'ownerId'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => throw const PropertyLimitFailure()),
      build: build,
      seed: () => const NewPropertyState(
        properties: [house],
        type: PropertyType.parking,
      ),
      act: (cubit) => cubit.submit(),
      skip: 1,
      expect: () => [
        isA<NewPropertyState>().having(
          (s) => s.status,
          'status',
          NewPropertyStatus.limitReached,
        ),
      ],
      errors: () => [isA<PropertyLimitFailure>()],
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'reports a failed creation',
      setUp: () => when(
        () => repository.createProperty(
          id: any(named: 'id'),
          ownerId: any(named: 'ownerId'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => throw const PropertySaveFailure()),
      build: build,
      seed: () => const NewPropertyState(
        properties: [house],
        type: PropertyType.parking,
      ),
      act: (cubit) => cubit.submit(),
      skip: 1,
      expect: () => [
        isA<NewPropertyState>().having(
          (s) => s.status,
          'status',
          NewPropertyStatus.failure,
        ),
      ],
      errors: () => [isA<PropertySaveFailure>()],
    );

    test('retries only the failed copy', () async {
      var copies = 0;
      when(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) async {
        if (copies++ == 0) throw const DocumentUploadFailure();
        return identity;
      });
      final cubit = build()..typeSelected(PropertyType.parking);
      await cubit.submit();
      expect(cubit.state.status, NewPropertyStatus.copyFailure);
      expect(cubit.state.property, created);
      await cubit.submit();
      expect(cubit.state.status, NewPropertyStatus.success);
      verify(
        () => repository.createProperty(
          id: 'new-id',
          ownerId: ownerId,
          type: PropertyType.parking,
        ),
      ).called(1);
      verify(
        () => repository.copyOwners(
          fromPropertyId: 'house',
          toPropertyId: 'new-id',
        ),
      ).called(1);
      // Already copied documents are not copied again.
      await cubit.submit();
      verify(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).called(2);
      await cubit.close();
    });

    test('copies nothing without a source or owners, and ignores a submit '
        'in progress', () async {
      when(
        () => repository.copyOwners(
          fromPropertyId: any(named: 'fromPropertyId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) async => []);
      final cubit = build()..typeSelected(PropertyType.parking);
      final first = cubit.submit();
      await cubit.submit();
      await first;
      expect(cubit.state.status, NewPropertyStatus.success);
      verifyNever(() => repository.updateProperty(any(), any()));
      await cubit.close();
      clearInteractions(repository);

      final alone = build(properties: const [])
        ..typeSelected(PropertyType.house);
      await alone.submit();
      expect(alone.state.status, NewPropertyStatus.success);
      verifyNever(() => repository.getDocuments(any()));
      await alone.close();
    });
  });
}
