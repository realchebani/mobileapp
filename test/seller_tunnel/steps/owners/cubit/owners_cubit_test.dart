import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/cubit/owners_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const _owner1 = PropertyOwner(
  id: 'o1',
  propertyId: 'p',
  position: 1,
  profileId: 'u',
  firstName: 'Sophie',
  lastName: 'Durand',
  phone: '+33612345678',
  email: 'sophie@email.fr',
);
const _owner2 = PropertyOwner(
  id: 'o2',
  propertyId: 'p',
  position: 2,
  firstName: 'Marc',
  lastName: 'Durand',
  phone: '+33698765432',
);
const _owner3 = PropertyOwner(
  id: 'o3',
  propertyId: 'p',
  position: 3,
  firstName: 'Léa',
  lastName: 'Durand',
  phone: '+33600000000',
);
const _newCoOwner = OwnerDraft(
  firstName: 'Paul',
  lastName: 'Martin',
  phone: '07 11 22 33 44',
);
const _validOwner = OwnerDraft(
  firstName: 'Sophie',
  lastName: 'Durand',
  phone: '06 12 34 56 78',
  email: 'sophie@email.fr',
);

void main() {
  late MockPropertyRepository repository;

  setUpAll(() => registerFallbackValue(_owner1));

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.deleteOwner(any())).thenAnswer((_) async {});
    var next = 10;
    when(() => repository.saveOwner(any())).thenAnswer((invocation) async {
      final row = invocation.positionalArguments.single as PropertyOwner;
      return PropertyOwner(
        id: row.id ?? 'o${next++}',
        propertyId: row.propertyId,
        position: row.position,
        profileId: row.profileId,
        firstName: row.firstName,
        lastName: row.lastName,
        phone: row.phone,
        email: row.email,
      );
    });
  });

  OwnersCubit build({
    List<PropertyOwner> owners = const [],
    OwnershipType? ownershipType,
    String? firstName,
    String? email,
  }) => OwnersCubit(
    propertyRepository: repository,
    propertyId: 'p',
    profileId: 'u',
    owners: owners,
    ownershipType: ownershipType,
    firstName: firstName,
    email: email,
  );

  group(OwnersCubit, () {
    test('starts from the saved owners', () {
      final state = build(
        owners: [_owner1, _owner2],
        ownershipType: OwnershipType.multiple,
        firstName: 'Ignored',
      ).state;
      expect(state.owner, OwnerDraft.fromOwner(_owner1));
      expect(state.coOwners, [OwnerDraft.fromOwner(_owner2)]);
      expect(state.saved, [_owner1, _owner2]);
      expect(state.ownershipType, OwnershipType.multiple);
    });

    test('prefills owner 1 without saved owners', () {
      expect(
        build(firstName: 'Sophie', email: 's@e.fr').state.owner,
        const OwnerDraft(firstName: 'Sophie', email: 's@e.fr'),
      );
      expect(build().state.owner, const OwnerDraft());
    });

    blocTest<OwnersCubit, OwnersState>(
      'edits the form',
      build: build,
      act: (cubit) => cubit
        ..ownershipSelected(OwnershipType.multiple)
        ..firstNameChanged('Sophie')
        ..lastNameChanged('Durand')
        ..phoneChanged('06')
        ..emailChanged('s@e.fr')
        ..fieldLeft(OwnerField.phone)
        ..fieldLeft(OwnerField.phone)
        ..coOwnerAdded(const OwnerDraft(firstName: 'A'))
        ..coOwnerAdded(const OwnerDraft(firstName: 'B'))
        ..coOwnerRemoved(0),
      skip: 8,
      expect: () => [
        const OwnersState(
          ownershipType: OwnershipType.multiple,
          owner: OwnerDraft(
            firstName: 'Sophie',
            lastName: 'Durand',
            phone: '06',
            email: 's@e.fr',
          ),
          touched: {OwnerField.phone},
          coOwners: [OwnerDraft(firstName: 'B')],
        ),
      ],
    );

    blocTest<OwnersCubit, OwnersState>(
      'keeps the saved row of an edited co-owner',
      build: () => build(owners: [_owner2]),
      act: (cubit) => cubit.coOwnerEdited(0, _newCoOwner),
      expect: () => [
        isA<OwnersState>().having((s) => s.coOwners, 'coOwners', [
          _newCoOwner.copyWith(id: 'o2'),
        ]),
      ],
    );

    group('submit', () {
      blocTest<OwnersCubit, OwnersState>(
        'shows every error while invalid',
        build: build,
        act: (cubit) async {
          await cubit.submit();
          await cubit.submit();
        },
        expect: () => const [
          OwnersState(showErrors: true, submitAttempts: 1),
          OwnersState(showErrors: true, submitAttempts: 2),
        ],
      );

      test('ignores edits while saving and saves the type it started '
          'with', () async {
        final completer = Completer<PropertyOwner>();
        when(() => repository.saveOwner(any()))
            .thenAnswer((_) => completer.future);
        final cubit = build(
          owners: [_owner1, _owner2],
          ownershipType: OwnershipType.multiple,
        )..phoneChanged('07 00 00 00 00');
        final before = cubit.state;
        final submit = cubit.submit();
        expect(cubit.state.submittedOwnershipType, OwnershipType.multiple);
        final saving = cubit.state;
        cubit
          ..ownershipSelected(OwnershipType.single)
          ..firstNameChanged('X')
          ..lastNameChanged('X')
          ..phoneChanged('X')
          ..emailChanged('X')
          ..fieldLeft(OwnerField.email)
          ..coOwnerAdded(_newCoOwner)
          ..coOwnerEdited(0, _newCoOwner)
          ..coOwnerRemoved(0);
        expect(cubit.state, saving);
        completer.complete(_owner1);
        await submit;
        expect(cubit.state.submitStatus, OwnersSubmitStatus.success);
        expect(cubit.state.owner, before.owner);
        expect(cubit.state.coOwners, before.coOwners);
        expect(cubit.state.submittedOwnershipType, OwnershipType.multiple);
        await cubit.close();
      });

      test(
        'adopts rows whose insert answer was lost before retrying',
        () async {
          // The insert of the new co-owner reaches the database, but its
          // answer is lost.
          when(
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.position, 'p', 3)),
            ),
          ).thenThrow(const PropertySaveFailure());
          final cubit =
              build(
                  owners: [_owner1, _owner2],
                  ownershipType: OwnershipType.multiple,
                )
                ..coOwnerAdded(_newCoOwner)
                ..coOwnerAdded(
                  const OwnerDraft(
                    firstName: 'Zoé',
                    lastName: 'Roy',
                    phone: '06 00 00 00 01',
                  ),
                );
          await cubit.submit();
          expect(cubit.state.submitStatus, OwnersSubmitStatus.failure);

          const inserted = PropertyOwner(
            id: 'lost',
            propertyId: 'p',
            position: 3,
            firstName: 'Paul',
            lastName: 'Martin',
            phone: '+33711223344',
          );
          when(() => repository.getOwners('p'))
              .thenAnswer((_) async => [_owner1, _owner2, inserted]);
          when(
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.position, 'p', 3)),
            ),
          ).thenAnswer((_) async => inserted);
          await cubit.submit();

          expect(cubit.state.submitStatus, OwnersSubmitStatus.success);
          expect(
            [for (final o in cubit.state.coOwners) o.id],
            ['o2', 'lost', 'o10'],
          );
          verify(() => repository.getOwners('p')).called(1);
          // The adopted row is unchanged: only Zoé is inserted.
          verify(
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.position, 'p', 3)),
            ),
          ).called(1);
          await cubit.close();
        },
      );

      test('keeps reloading until the rows could be reloaded', () async {
        when(() => repository.deleteOwner(any()))
            .thenThrow(const PropertyDeleteFailure());
        final cubit = build(
          owners: [_owner1, _owner2],
          ownershipType: OwnershipType.single,
        );
        await cubit.submit();
        when(() => repository.getOwners('p'))
            .thenThrow(const PropertyLoadFailure());
        await cubit.submit();
        when(() => repository.getOwners('p'))
            .thenAnswer((_) async => [_owner1]);
        await cubit.submit();
        expect(cubit.state.submitStatus, OwnersSubmitStatus.success);
        verify(() => repository.getOwners('p')).called(2);
        await cubit.close();
      });

      blocTest<OwnersCubit, OwnersState>(
        'saves a single owner and removes the co-owners',
        build: () => build(
          owners: [_owner1, _owner2],
          ownershipType: OwnershipType.single,
        ),
        act: (cubit) => (cubit..phoneChanged('07 00 00 00 00')).submit(),
        skip: 2,
        expect: () => [
          isA<OwnersState>()
              .having(
                (s) => s.submitStatus,
                'status',
                OwnersSubmitStatus.success,
              )
              .having((s) => s.coOwners, 'coOwners', isEmpty)
              .having((s) => s.saved.single.phone, 'phone', '+33700000000'),
        ],
        verify: (_) {
          verifyInOrder([
            () => repository.deleteOwner('o2'),
            () => repository.saveOwner(
              const PropertyOwner(
                id: 'o1',
                propertyId: 'p',
                position: 1,
                profileId: 'u',
                firstName: 'Sophie',
                lastName: 'Durand',
                phone: '+33700000000',
                email: 'sophie@email.fr',
              ),
            ),
          ]);
        },
      );

      blocTest<OwnersCubit, OwnersState>(
        'deletes, moves down and inserts co-owners, skipping unchanged rows',
        build: () => build(
          owners: [_owner1, _owner2, _owner3],
          ownershipType: OwnershipType.multiple,
        ),
        act: (cubit) =>
            (cubit
                  ..coOwnerRemoved(0)
                  ..coOwnerAdded(_newCoOwner))
                .submit(),
        skip: 3,
        expect: () => [
          isA<OwnersState>()
              .having(
                (s) => s.submitStatus,
                'status',
                OwnersSubmitStatus.success,
              )
              .having(
                (s) => [for (final o in s.saved) '${o.id}@${o.position}'],
                'saved',
                ['o1@1', 'o3@2', 'o10@3'],
              )
              .having(
                (s) => [for (final o in s.coOwners) o.id],
                'coOwner ids',
                ['o3', 'o10'],
              ),
        ],
        verify: (_) {
          verifyInOrder([
            () => repository.deleteOwner('o2'),
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.id, 'id', 'o3')),
            ),
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.id, 'id', null)),
            ),
          ]);
          verifyNever(
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.id, 'id', 'o1')),
            ),
          );
        },
      );

      blocTest<OwnersCubit, OwnersState>(
        'inserts owner 1 and ignores a second submit while saving',
        build: () => build(ownershipType: OwnershipType.single)
          ..firstNameChanged(_validOwner.firstName)
          ..lastNameChanged(_validOwner.lastName)
          ..phoneChanged(_validOwner.phone)
          ..emailChanged(_validOwner.email),
        act: (cubit) async {
          unawaited(cubit.submit());
          await cubit.submit();
        },
        expect: () => [
          isA<OwnersState>().having(
            (s) => s.submitStatus,
            'status',
            OwnersSubmitStatus.inProgress,
          ),
          isA<OwnersState>()
              .having((s) => s.owner.id, 'owner id', 'o10')
              .having((s) => s.saved.single.profileId, 'profile', 'u'),
        ],
        verify: (_) => verify(() => repository.saveOwner(any())).called(1),
      );

      blocTest<OwnersCubit, OwnersState>(
        'keeps the progress on failure',
        setUp: () {
          when(
            () => repository.saveOwner(
              any(that: isA<PropertyOwner>().having((o) => o.position, 'p', 2)),
            ),
          ).thenThrow(const PropertySaveFailure());
        },
        build: () =>
            build(owners: [_owner2], ownershipType: OwnershipType.multiple)
              ..firstNameChanged(_validOwner.firstName)
              ..lastNameChanged(_validOwner.lastName)
              ..phoneChanged(_validOwner.phone)
              ..emailChanged(_validOwner.email)
              ..coOwnerRemoved(0)
              ..coOwnerAdded(_newCoOwner),
        act: (cubit) => cubit.submit(),
        skip: 1,
        expect: () => [
          isA<OwnersState>()
              .having(
                (s) => s.submitStatus,
                'status',
                OwnersSubmitStatus.failure,
              )
              .having((s) => s.owner.id, 'owner id', 'o10')
              .having((s) => s.coOwners, 'coOwners', [_newCoOwner])
              .having((s) => [for (final o in s.saved) o.id], 'saved', ['o10']),
        ],
        errors: () => [isA<PropertySaveFailure>()],
      );

      blocTest<OwnersCubit, OwnersState>(
        'keeps the co-owners when a single owner fails to save',
        setUp: () {
          when(() => repository.deleteOwner(any()))
              .thenThrow(const PropertyDeleteFailure());
        },
        build: () => build(
          owners: [_owner1, _owner2],
          ownershipType: OwnershipType.single,
        ),
        act: (cubit) => cubit.submit(),
        skip: 1,
        expect: () => [
          isA<OwnersState>()
              .having(
                (s) => s.submitStatus,
                'status',
                OwnersSubmitStatus.failure,
              )
              .having((s) => s.coOwners.length, 'coOwners', 1),
        ],
        errors: () => [isA<PropertyDeleteFailure>()],
      );

      test('stops after being closed', () async {
        final completer = Completer<PropertyOwner>();
        when(() => repository.saveOwner(any()))
            .thenAnswer((_) => completer.future);
        final cubit = build(
          owners: [_owner1],
          ownershipType: OwnershipType.single,
        )..phoneChanged('07 00 00 00 00');
        final submit = cubit.submit();
        await cubit.close();
        completer.complete(_owner1);
        await submit;

        final failing = Completer<PropertyOwner>();
        when(() => repository.saveOwner(any()))
            .thenAnswer((_) => failing.future);
        final other = build(
          owners: [_owner1],
          ownershipType: OwnershipType.single,
        )..phoneChanged('07 00 00 00 00');
        final otherSubmit = other.submit();
        await other.close();
        failing.completeError(const PropertySaveFailure());
        await otherSubmit;
        expect(other.state.submitStatus, OwnersSubmitStatus.inProgress);
      });
    });
  });

  group(OwnersState, () {
    test('isValid', () {
      expect(const OwnersState(owner: _validOwner).isValid, isFalse);
      expect(
        const OwnersState(
          ownershipType: OwnershipType.single,
          owner: _validOwner,
        ).isValid,
        isTrue,
      );
      expect(
        const OwnersState(
          ownershipType: OwnershipType.multiple,
          owner: _validOwner,
        ).isValid,
        isFalse,
      );
      expect(
        const OwnersState(
          ownershipType: OwnershipType.multiple,
          owner: _validOwner,
          coOwners: [_newCoOwner],
        ).isValid,
        isTrue,
      );
      expect(
        const OwnersState(ownershipType: OwnershipType.single).isValid,
        isFalse,
      );
    });

    test('shows the missing answers after "Continuer"', () {
      const state = OwnersState(showErrors: true);
      expect(state.ownershipMissing, isTrue);
      expect(state.errorOf(OwnerField.firstName), OwnerFieldError.required);
      expect(const OwnersState().ownershipMissing, isFalse);
      expect(
        const OwnersState(
          showErrors: true,
          ownershipType: OwnershipType.multiple,
        ).coOwnersMissing,
        isTrue,
      );
      expect(
        const OwnersState(
          showErrors: true,
          ownershipType: OwnershipType.multiple,
          coOwners: [_newCoOwner],
        ).coOwnersMissing,
        isFalse,
      );
    });

    test('errorOf shows the errors of the fields left', () {
      const untouched = OwnersState();
      for (final field in OwnerField.values) {
        expect(untouched.errorOf(field), isNull);
      }
      final touched = untouched.copyWith(
        touched: OwnerField.values.toSet(),
        owner: const OwnerDraft(phone: '1', email: 'x'),
      );
      expect(touched.errorOf(OwnerField.firstName), OwnerFieldError.required);
      expect(touched.errorOf(OwnerField.lastName), OwnerFieldError.required);
      expect(touched.errorOf(OwnerField.phone), OwnerFieldError.invalidPhone);
      expect(touched.errorOf(OwnerField.email), OwnerFieldError.invalidEmail);
    });
  });
}
