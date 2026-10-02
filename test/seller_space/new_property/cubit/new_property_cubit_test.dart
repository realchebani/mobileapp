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
    when(() => repository.getDocuments('new-id')).thenAnswer((_) async => []);
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
      expect(
        const NewPropertyState(
          properties: [
            Property(id: 'a', ownerId: ownerId, lotId: 'l'),
            Property(
              id: 'b',
              ownerId: ownerId,
              lotId: 'l',
              status: PropertyStatus.inReview,
            ),
            Property(
              id: 'c',
              ownerId: ownerId,
              status: PropertyStatus.submitted,
            ),
          ],
        ).partners.map((p) => p.id),
        ['c'],
      );
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
        // The property is known as soon as it is created.
        isA<NewPropertyState>()
            .having((s) => s.status, 'status', NewPropertyStatus.inProgress)
            .having((s) => s.property, 'property', created),
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
            PropertyColumns.provenance: {
              PropertyColumns.ownershipType: 'declared',
              Property.ownersCopiedFromKey: 'house',
            },
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
      'creates a lot with the partner, all at once',
      setUp: () =>
          when(
            () => repository.createLotWith(
              id: 'new-id',
              propertyIds: ['house', 'new-id'],
            ),
          ).thenAnswer(
            (_) async => const PropertyLot(
              id: 'new-id',
              ownerId: ownerId,
              mainPropertyId: 'house',
            ),
          ),
      build: build,
      seed: () => const NewPropertyState(
        properties: [house],
        type: PropertyType.parking,
        partnerId: 'house',
        reuseOwners: false,
        reuseIdentity: false,
      ),
      act: (cubit) => cubit.submit(),
      verify: (cubit) {
        expect(cubit.state.status, NewPropertyStatus.success);
        expect(cubit.state.lot?.mainPropertyId, 'house');
      },
    );

    blocTest<NewPropertyCubit, NewPropertyState>(
      'joins the lot of the partner',
      setUp: () =>
          when(() => repository.setPropertyLot('new-id', 'lot'))
              .thenAnswer((_) async => created),
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
        expect(cubit.state.status, NewPropertyStatus.success);
        verify(() => repository.setPropertyLot('new-id', 'lot')).called(1);
      },
    );

    test('a failed lot keeps the property and retries the lot only', () async {
      var calls = 0;
      when(
        () => repository.createLotWith(
          id: any(named: 'id'),
          propertyIds: any(named: 'propertyIds'),
        ),
      ).thenAnswer((_) async {
        if (calls++ == 0) throw const PropertySaveFailure();
        return lot;
      });
      final cubit = build()
        ..typeSelected(PropertyType.parking)
        ..partnerSelected('house')
        ..reuseOwnersChanged(reuse: false)
        ..reuseIdentityChanged(reuse: false);
      await cubit.submit();
      expect(cubit.state.status, NewPropertyStatus.lotFailure);
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
      // Joined: not again.
      await cubit.submit();
      expect(calls, 2);
      await cubit.close();
    });

    test('never copies a document twice', () async {
      when(() => repository.getDocuments('new-id')).thenAnswer(
        (_) async => const [
          PropertyDocument(
            id: 'copy',
            propertyId: 'new-id',
            kind: DocumentKind.identityDocument,
            storagePath: 'user-id/new-id/id.pdf',
          ),
        ],
      );
      final cubit = build()..typeSelected(PropertyType.parking);
      await cubit.submit();
      expect(cubit.state.status, NewPropertyStatus.success);
      verifyNever(
        () => repository.copyDocument(
          any(),
          ownerId: any(named: 'ownerId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      );
      await cubit.close();
    });

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
