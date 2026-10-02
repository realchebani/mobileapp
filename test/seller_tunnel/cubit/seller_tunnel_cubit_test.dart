import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';

void main() {
  const ownerId = 'user-id';
  const property = testProperty;
  const owner = PropertyOwner(
    propertyId: 'property-id',
    position: 1,
    firstName: 'Sophie',
    lastName: 'Durand',
  );
  const room = Room(propertyId: 'property-id', name: 'WC', areaM2: 2);

  late PropertyRepository repository;

  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
  });

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.getProperty(any())).thenAnswer((_) async => property);
    when(() => repository.getOwners(any())).thenAnswer((_) async => [owner]);
    when(() => repository.getParcels(any())).thenAnswer((_) async => []);
    when(() => repository.getPreviousEstimates(any()))
        .thenAnswer((_) async => []);
    when(() => repository.getRooms(any())).thenAnswer((_) async => [room]);
    when(() => repository.getLifestyleItems(any())).thenAnswer((_) async => []);
    when(() => repository.getDocuments(any())).thenAnswer((_) async => []);
  });

  SellerTunnelCubit build({Duration timeout = const Duration(seconds: 1)}) =>
      SellerTunnelCubit(
        propertyRepository: repository,
        propertyId: 'property-id',
        timeout: timeout,
      );

  const loaded = SellerTunnelState(
    status: SellerTunnelStatus.success,
    property: property,
    owners: [owner],
    rooms: [room],
  );

  test('initial state', () {
    expect(build().state, const SellerTunnelState());
  });

  group('load', () {
    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'loads the draft and its children',
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => const [
        SellerTunnelState(status: SellerTunnelStatus.loading),
        loaded,
      ],
      verify: (_) {
        verify(() => repository.getProperty('property-id')).called(1);
        verify(() => repository.getDocuments('property-id')).called(1);
      },
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'fails when the draft cannot be loaded, then retries',
      setUp: () {
        var calls = 0;
        when(() => repository.getProperty(any())).thenAnswer((_) async {
          if (calls++ == 0) throw const PropertyLoadFailure();
          return property;
        });
      },
      build: build,
      act: (cubit) async {
        await cubit.load();
        await cubit.retry();
      },
      expect: () => const [
        SellerTunnelState(status: SellerTunnelStatus.loading),
        SellerTunnelState(status: SellerTunnelStatus.failure),
        SellerTunnelState(status: SellerTunnelStatus.loading),
        loaded,
      ],
      errors: () => [isA<PropertyLoadFailure>()],
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'fails when a child collection cannot be loaded',
      setUp: () =>
          when(() => repository.getRooms(any()))
              .thenAnswer((_) async => throw const PropertyLoadFailure()),
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => const [
        SellerTunnelState(status: SellerTunnelStatus.loading),
        SellerTunnelState(status: SellerTunnelStatus.failure),
      ],
      errors: () => [isA<ParallelWaitError<Object?, Object?>>()],
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'fails after the timeout',
      setUp: () =>
          when(() => repository.getProperty(any()))
              .thenAnswer((_) => Completer<Property>().future),
      build: () => build(timeout: const Duration(milliseconds: 10)),
      act: (cubit) => cubit.load(),
      wait: const Duration(milliseconds: 50),
      expect: () => const [
        SellerTunnelState(status: SellerTunnelStatus.loading),
        SellerTunnelState(status: SellerTunnelStatus.failure),
      ],
      errors: () => [isA<TimeoutException>()],
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'ignores a load while loading',
      build: build,
      seed: () => const SellerTunnelState(status: SellerTunnelStatus.loading),
      act: (cubit) => cubit.load(),
      expect: () => const <SellerTunnelState>[],
    );

    test('ignores results after close', () async {
      final completer = Completer<Property>();
      when(() => repository.getProperty(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build();
      final loading = cubit.load();
      await cubit.close();
      completer.complete(property);
      await loading;
      expect(cubit.state.status, SellerTunnelStatus.loading);
    });

    test('ignores failures after close', () async {
      final completer = Completer<Property>();
      when(() => repository.getProperty(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build();
      final loading = cubit.load();
      await cubit.close();
      completer.completeError(const PropertyLoadFailure());
      await loading;
      expect(cubit.state.status, SellerTunnelStatus.loading);
    });
  });

  group('saveAndContinue', () {
    const updated = Property(
      id: 'property-id',
      ownerId: ownerId,
      currentStep: 2,
      ownershipType: OwnershipType.single,
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'saves the patch and the resume point, then targets the next step',
      setUp: () =>
          when(() => repository.updateProperty(any(), any()))
              .thenAnswer((_) async => updated),
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit.saveAndContinue(SellerTunnelStep.owners, {
        PropertyColumns.ownershipType: OwnershipType.single,
      }),
      expect: () => [
        loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
        loaded.copyWith(
          property: updated,
          saveStatus: SellerTunnelSaveStatus.success,
          nextStep: SellerTunnelStep.location,
          continuedFrom: SellerTunnelStep.owners,
        ),
      ],
      verify: (_) => verify(
        () => repository.updateProperty('property-id', {
          PropertyColumns.ownershipType: OwnershipType.single,
          PropertyColumns.currentStep: 2,
        }),
      ).called(1),
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'keeps a further resume point when going back through a step',
      setUp: () =>
          when(() => repository.updateProperty(any(), any()))
              .thenAnswer((_) async => updated),
      build: build,
      seed: () => loaded.copyWith(
        property: const Property(
          id: 'property-id',
          ownerId: ownerId,
          currentStep: 6,
        ),
      ),
      act: (cubit) => cubit.saveAndContinue(SellerTunnelStep.location),
      verify: (_) => verify(
        () => repository.updateProperty('property-id', {
          PropertyColumns.currentStep: 6,
        }),
      ).called(1),
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'reports a failure',
      setUp: () =>
          when(() => repository.updateProperty(any(), any()))
              .thenThrow(const PropertySaveFailure()),
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit.saveAndContinue(SellerTunnelStep.owners),
      expect: () => [
        loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
        loaded.copyWith(saveStatus: SellerTunnelSaveStatus.failure),
      ],
      errors: () => [isA<PropertySaveFailure>()],
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'does nothing before the dossier is loaded or while saving',
      build: build,
      act: (cubit) async {
        await cubit.saveAndContinue(SellerTunnelStep.owners);
        cubit.emit(
          loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
        );
        await cubit.save(const {});
      },
      expect: () => [
        loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
      ],
      verify: (_) => verifyNever(() => repository.updateProperty(any(), any())),
    );
  });

  group('save', () {
    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'saves the patch without targeting a step',
      setUp: () =>
          when(() => repository.updateProperty(any(), any()))
              .thenAnswer((_) async => property),
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit.save(const {PropertyColumns.notifyPush: false}),
      expect: () => [
        loaded.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
        loaded.copyWith(saveStatus: SellerTunnelSaveStatus.success),
      ],
    );

    test('ignores results after close', () async {
      final completer = Completer<Property>();
      when(() => repository.updateProperty(any(), any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..emit(loaded);
      final saving = cubit.save(const {});
      await cubit.close();
      completer.complete(property);
      await saving;
      expect(cubit.state.saveStatus, SellerTunnelSaveStatus.inProgress);
    });

    test('ignores failures after close', () async {
      final completer = Completer<Property>();
      when(() => repository.updateProperty(any(), any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..emit(loaded);
      final saving = cubit.save(const {});
      await cubit.close();
      completer.completeError(const PropertySaveFailure());
      await saving;
      expect(cubit.state.saveStatus, SellerTunnelSaveStatus.inProgress);
    });
  });

  blocTest<SellerTunnelCubit, SellerTunnelState>(
    'updateChildren replaces the given collections',
    build: build,
    seed: () => loaded,
    act: (cubit) => cubit.updateChildren(
      owners: const [],
      parcels: const [PropertyParcel(propertyId: 'property-id', idu: 'x')],
      previousEstimates: const [],
      lifestyleItems: const [],
      documents: const [],
    ),
    expect: () => [
      loaded.copyWith(
        owners: const [],
        parcels: const [PropertyParcel(propertyId: 'property-id', idu: 'x')],
      ),
    ],
  );

  group('refresh', () {
    const certified = Property(
      id: 'property-id',
      ownerId: ownerId,
      status: PropertyStatus.certified,
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'reloads the dossier without a loading state',
      setUp: () {
        when(() => repository.getProperty(any()))
            .thenAnswer((_) async => certified);
        when(() => repository.getRooms(any())).thenAnswer((_) async => []);
      },
      build: build,
      seed: () => loaded,
      act: (cubit) => cubit.refresh(),
      expect: () => [loaded.copyWith(property: certified, rooms: const [])],
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'keeps the state when it fails',
      setUp: () {
        when(() => repository.getProperty(any()))
            .thenThrow(const PropertyLoadFailure());
      },
      build: build,
      seed: () => loaded,
      act: (cubit) =>
          expectLater(cubit.refresh(), throwsA(isA<PropertyLoadFailure>())),
      expect: () => const <SellerTunnelState>[],
      errors: () => [isA<PropertyLoadFailure>()],
    );

    blocTest<SellerTunnelCubit, SellerTunnelState>(
      'does nothing before the dossier is loaded',
      build: build,
      act: (cubit) => cubit.refresh(),
      expect: () => const <SellerTunnelState>[],
    );

    test('ignores an answer arriving after close', () async {
      final completer = Completer<Property>();
      when(() => repository.getProperty(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..emit(loaded);
      final refreshing = cubit.refresh();
      await cubit.close();
      completer.complete(certified);
      await refreshing;
      expect(cubit.state, loaded);
    });

    test('ignores a failure arriving after close', () async {
      final completer = Completer<Property>();
      when(() => repository.getProperty(any()))
          .thenAnswer((_) => completer.future);
      final cubit = build()..emit(loaded);
      final refreshing = cubit.refresh();
      await cubit.close();
      completer.completeError(const PropertyLoadFailure());
      await expectLater(refreshing, throwsA(anything));
    });
  });

  group(SellerTunnelState, () {
    test('resumes at the current step', () {
      expect(const SellerTunnelState().resumeStep, SellerTunnelStep.owners);
      expect(
        const SellerTunnelState(
          property: Property(id: 'p', ownerId: 'u', currentStep: 5),
        ).resumeStep,
        SellerTunnelStep.method,
      );
    });

    test('is locked once the dossier is sent', () {
      expect(const SellerTunnelState().isLocked, isFalse);
      for (final status in PropertyStatus.values) {
        final state = SellerTunnelState(
          property: Property(
            id: 'p',
            ownerId: 'u',
            status: status,
            currentStep: 3,
          ),
        );
        final locked = status != PropertyStatus.draft;
        expect(state.isLocked, locked, reason: status.name);
        expect(
          state.resumeStep,
          locked ? SellerTunnelStep.submitted : SellerTunnelStep.context,
          reason: status.name,
        );
      }
    });

    test('redirects the editable steps of a sent dossier to V8', () {
      const draft = SellerTunnelState(
        property: Property(
          id: 'p',
          ownerId: 'u',
          currentStep: 8,
          propertyType: PropertyType.house,
        ),
      );
      for (final step in SellerTunnelStep.values) {
        expect(draft.redirectFor(step.segment), isNull);
      }
      expect(draft.redirectFor(SellerTunnelStep.voiceAuditSegment), isNull);
      expect(const SellerTunnelState().redirectFor('technique'), isNull);
      for (final status in [
        PropertyStatus.submitted,
        PropertyStatus.inReview,
        PropertyStatus.certified,
      ]) {
        final state = SellerTunnelState(
          property: Property(
            id: 'p',
            ownerId: 'u',
            status: status,
            currentStep: 8,
          ),
        );
        for (final step in SellerTunnelStep.values) {
          expect(
            state.redirectFor(step.segment),
            step == SellerTunnelStep.submitted
                ? isNull
                : '/vendeur/biens/p/audit/envoye',
            reason: '${status.name} ${step.name}',
          );
        }
        expect(
          state.redirectFor(SellerTunnelStep.voiceAuditSegment),
          '/vendeur/biens/p/audit/envoye',
        );
        expect(state.redirectFor('inconnu'), isNull);
      }
    });

    test('redirects the screens a type skips', () {
      const garage = SellerTunnelState(
        property: Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.parking,
        ),
      );
      expect(garage.redirectFor('methode'), '/vendeur/biens/p/audit/documents');
      expect(
        garage.redirectFor('cadre-de-vie'),
        '/vendeur/biens/p/audit/documents',
      );
      expect(
        garage.redirectFor(SellerTunnelStep.voiceAuditSegment),
        '/vendeur/biens/p/audit/technique',
      );
      expect(garage.redirectFor('technique'), isNull);
      expect(garage.profile.type, PropertyType.parking);
      expect(
        const SellerTunnelState(
          property: Property(
            id: 'p',
            ownerId: 'u',
            propertyType: PropertyType.parking,
            currentStep: 5,
          ),
        ).resumeStep,
        SellerTunnelStep.documents,
      );
    });

    test('copyWith keeps values and resets nextStep', () {
      const state = SellerTunnelState(
        saveStatus: SellerTunnelSaveStatus.success,
        nextStep: SellerTunnelStep.location,
        continuedFrom: SellerTunnelStep.owners,
      );
      expect(state.copyWith().saveStatus, SellerTunnelSaveStatus.success);
      expect(state.copyWith().nextStep, isNull);
      expect(state.copyWith().continuedFrom, isNull);
      expect(state.isSaving, isFalse);
    });
  });
}
