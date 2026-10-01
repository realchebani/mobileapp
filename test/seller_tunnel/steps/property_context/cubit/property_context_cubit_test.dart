import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/cubit/property_context_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

final _today = DateTime(2026, 10);

const _estimate = PreviousEstimate(
  id: 'e1',
  propertyId: 'property-id',
  priceEur: 510000,
  agencyName: 'Agence du Port',
);

/// A dossier with every required answer, not estimated.
const _answered = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
  purchaseYear: 2012,
  selfBuilt: false,
  previouslyEstimated: false,
);

/// A state with every required answer.
PropertyContextState _valid({
  bool? previouslyEstimated,
  List<EstimateDraft> estimates = const [],
}) => PropertyContextState(
  today: _today,
  propertyType: PropertyType.house,
  purchaseYear: '2012',
  selfBuilt: false,
  previouslyEstimated: previouslyEstimated,
  estimates: estimates,
);

void main() {
  late MockPropertyRepository repository;

  setUpAll(() => registerFallbackValue(_estimate));

  setUp(() => repository = MockPropertyRepository());

  PropertyContextCubit build({
    Property property = testProperty,
    List<PreviousEstimate> estimates = const [],
  }) => PropertyContextCubit(
    propertyRepository: repository,
    property: property,
    estimates: estimates,
    today: _today,
  );

  group('PropertyContextCubit', () {
    test('starts empty for a new dossier', () {
      expect(build().state, PropertyContextState(today: _today));
    });

    test('defaults today to now', () {
      final cubit = PropertyContextCubit(
        propertyRepository: repository,
        property: testProperty,
      );
      expect(cubit.state.today.year, DateTime.now().year);
    });

    test('starts from the saved answers and estimates', () {
      final cubit = build(
        property: const Property(
          id: 'property-id',
          ownerId: 'user-id',
          propertyType: PropertyType.other,
          propertyTypeOther: 'Local',
          purchaseYear: 2012,
          purchasePriceEur: 320000,
          selfBuilt: true,
          saleReason: SaleReason.moreSpace,
          previouslyEstimated: true,
        ),
        estimates: [
          _estimate,
          PreviousEstimate(
            id: 'e2',
            propertyId: 'property-id',
            priceEur: 480000,
            estimatedMonth: DateTime(2024, 3),
          ),
        ],
      );
      expect(
        cubit.state,
        PropertyContextState(
          today: _today,
          propertyType: PropertyType.other,
          propertyTypeOther: 'Local',
          purchaseYear: '2012',
          purchasePrice: '320\u00a0000',
          selfBuilt: true,
          saleReason: SaleReason.moreSpace,
          previouslyEstimated: true,
          estimates: const [
            EstimateDraft(
              key: 0,
              id: 'e1',
              price: '510\u00a0000',
              agency: 'Agence du Port',
            ),
            EstimateDraft(
              key: 1,
              id: 'e2',
              price: '480\u00a0000',
              month: '03/2024',
            ),
          ],
        ),
      );
    });

    test('opens a card when estimated without saved estimates', () {
      final cubit = build(
        property: const Property(
          id: 'property-id',
          ownerId: 'user-id',
          previouslyEstimated: true,
        ),
      );
      expect(cubit.state.estimates, const [EstimateDraft(key: 0)]);
      cubit.estimateAdded();
      expect(cubit.state.estimates.last.key, isNot(0));
    });

    test('answers "Oui" when estimates exist without an answer', () {
      expect(build(estimates: [_estimate]).state.previouslyEstimated, isTrue);
    });

    blocTest<PropertyContextCubit, PropertyContextState>(
      'records the answers',
      build: build,
      act: (cubit) => cubit
        ..propertyTypeSelected(PropertyType.other)
        ..propertyTypeOtherChanged('Garage')
        ..purchaseYearChanged('2012')
        ..purchasePriceChanged('320 000')
        ..selfBuiltChanged(selfBuilt: true)
        ..saleReasonToggled(SaleReason.investment),
      skip: 5,
      expect: () => [
        PropertyContextState(
          today: _today,
          propertyType: PropertyType.other,
          propertyTypeOther: 'Garage',
          purchaseYear: '2012',
          purchasePrice: '320 000',
          selfBuilt: true,
          saleReason: SaleReason.investment,
        ),
      ],
    );

    blocTest<PropertyContextCubit, PropertyContextState>(
      'clears the sale reason when it is toggled again',
      build: build,
      act: (cubit) => cubit
        ..saleReasonToggled(SaleReason.separation)
        ..saleReasonToggled(SaleReason.separation),
      expect: () => [
        PropertyContextState(today: _today, saleReason: SaleReason.separation),
        PropertyContextState(today: _today),
      ],
    );

    blocTest<PropertyContextCubit, PropertyContextState>(
      'manages the estimate cards',
      build: build,
      act: (cubit) => cubit
        ..previouslyEstimatedChanged(previouslyEstimated: true)
        ..estimateAdded()
        ..estimateChanged(1, price: '1', month: '05/2020', agency: 'A')
        ..estimateRemoved(2)
        ..previouslyEstimatedChanged(previouslyEstimated: false)
        ..previouslyEstimatedChanged(previouslyEstimated: true),
      expect: () => [
        PropertyContextState(
          today: _today,
          previouslyEstimated: true,
          estimates: const [EstimateDraft(key: 1)],
        ),
        PropertyContextState(
          today: _today,
          previouslyEstimated: true,
          estimates: const [EstimateDraft(key: 1), EstimateDraft(key: 2)],
        ),
        PropertyContextState(
          today: _today,
          previouslyEstimated: true,
          estimates: const [
            EstimateDraft(key: 1, price: '1', month: '05/2020', agency: 'A'),
            EstimateDraft(key: 2),
          ],
        ),
        PropertyContextState(
          today: _today,
          previouslyEstimated: true,
          estimates: const [
            EstimateDraft(key: 1, price: '1', month: '05/2020', agency: 'A'),
          ],
        ),
        PropertyContextState(
          today: _today,
          previouslyEstimated: false,
          estimates: const [
            EstimateDraft(key: 1, price: '1', month: '05/2020', agency: 'A'),
          ],
        ),
        PropertyContextState(
          today: _today,
          previouslyEstimated: true,
          estimates: const [
            EstimateDraft(key: 1, price: '1', month: '05/2020', agency: 'A'),
          ],
        ),
      ],
    );

    group('submit', () {
      blocTest<PropertyContextCubit, PropertyContextState>(
        'shows the errors when answers are missing',
        build: build,
        act: (cubit) async {
          await cubit.submit();
          await cubit.submit();
        },
        expect: () => [
          PropertyContextState(
            today: _today,
            showErrors: true,
            submitAttempts: 1,
          ),
          PropertyContextState(
            today: _today,
            showErrors: true,
            submitAttempts: 2,
          ),
        ],
        verify: (_) => verifyZeroInteractions(repository),
      );

      blocTest<PropertyContextCubit, PropertyContextState>(
        'succeeds without estimates',
        build: build,
        seed: _valid,
        act: (cubit) => cubit.submit(),
        expect: () => [
          _valid().copyWith(
            showErrors: true,
            submission: PropertyContextSubmission.inProgress,
          ),
          _valid().copyWith(
            showErrors: true,
            submission: PropertyContextSubmission.success,
          ),
        ],
      );

      blocTest<PropertyContextCubit, PropertyContextState>(
        'saves new and changed estimates, keeps unchanged ones and '
        'deletes removed ones',
        setUp: () {
          when(() => repository.savePreviousEstimate(any()))
              .thenAnswer((invocation) async {
                final estimate =
                    invocation.positionalArguments.single as PreviousEstimate;
                return PreviousEstimate(
                  id: estimate.id ?? 'new',
                  propertyId: estimate.propertyId,
                  priceEur: estimate.priceEur,
                  estimatedMonth: estimate.estimatedMonth,
                  agencyName: estimate.agencyName,
                );
              });
          when(() => repository.deletePreviousEstimate(any()))
              .thenAnswer((_) async {});
        },
        build: () => build(
          estimates: [
            _estimate,
            const PreviousEstimate(
              id: 'e2',
              propertyId: 'property-id',
              priceEur: 400000,
            ),
            const PreviousEstimate(
              id: 'e3',
              propertyId: 'property-id',
              priceEur: 300000,
            ),
          ],
        ),
        seed: () => _valid(
          previouslyEstimated: true,
          estimates: const [
            EstimateDraft(
              key: 0,
              id: 'e1',
              price: '510\u00a0000',
              agency: ' Agence du Port ',
            ),
            EstimateDraft(key: 1, id: 'e2', price: '420 000'),
            EstimateDraft(key: 5, price: '450 000', month: '05/2020'),
          ],
        ),
        act: (cubit) async {
          await cubit.submit();
          // Nothing changed since: no more writes.
          await cubit.submit();
        },
        skip: 1,
        expect: () => [
          isA<PropertyContextState>()
              .having(
                (state) => state.submission,
                'submission',
                PropertyContextSubmission.success,
              )
              .having((state) => state.savedEstimates, 'savedEstimates', [
                _estimate,
                const PreviousEstimate(
                  id: 'e2',
                  propertyId: 'property-id',
                  priceEur: 420000,
                ),
                PreviousEstimate(
                  id: 'new',
                  propertyId: 'property-id',
                  priceEur: 450000,
                  estimatedMonth: DateTime(2020, 5),
                ),
              ])
              .having((state) => state.estimates.last.id, 'new id', 'new'),
          isA<PropertyContextState>().having(
            (state) => state.submission,
            'submission',
            PropertyContextSubmission.inProgress,
          ),
          isA<PropertyContextState>().having(
            (state) => state.submission,
            'submission',
            PropertyContextSubmission.success,
          ),
        ],
        verify: (_) {
          verify(() => repository.deletePreviousEstimate('e3')).called(1);
          verify(() => repository.savePreviousEstimate(any())).called(2);
        },
      );

      blocTest<PropertyContextCubit, PropertyContextState>(
        'deletes every estimate when the answer is "Non"',
        setUp: () =>
            when(() => repository.deletePreviousEstimate(any()))
                .thenAnswer((_) async {}),
        build: () => build(estimates: [_estimate]),
        seed: () => _valid(
          previouslyEstimated: false,
          estimates: const [EstimateDraft(key: 0, id: 'e1', price: '1 000')],
        ),
        act: (cubit) => cubit.submit(),
        skip: 1,
        expect: () => [
          _valid(previouslyEstimated: false).copyWith(
            showErrors: true,
            submission: PropertyContextSubmission.success,
          ),
        ],
        verify: (_) =>
            verify(() => repository.deletePreviousEstimate('e1')).called(1),
      );

      blocTest<PropertyContextCubit, PropertyContextState>(
        'fails when the estimates cannot be saved',
        setUp: () =>
            when(() => repository.savePreviousEstimate(any()))
                .thenThrow(Exception('offline')),
        build: build,
        seed: () => _valid(
          previouslyEstimated: true,
          estimates: const [EstimateDraft(key: 0, price: '1 000')],
        ),
        act: (cubit) => cubit.submit(),
        skip: 1,
        expect: () => [
          _valid(
            previouslyEstimated: true,
            estimates: const [EstimateDraft(key: 0, price: '1 000')],
          ).copyWith(
            showErrors: true,
            submission: PropertyContextSubmission.failure,
          ),
        ],
        errors: () => [isA<Exception>()],
      );

      blocTest<PropertyContextCubit, PropertyContextState>(
        'ignores a submission in progress',
        build: build,
        seed: () =>
            _valid().copyWith(submission: PropertyContextSubmission.inProgress),
        act: (cubit) => cubit.submit(),
        expect: () => <PropertyContextState>[],
      );

      test('updates the rows saved before a failure when retried', () async {
        var inserted = 0;
        var failSecond = true;
        when(() => repository.savePreviousEstimate(any()))
            .thenAnswer((invocation) async {
              final estimate =
                  invocation.positionalArguments.single as PreviousEstimate;
              if (estimate.priceEur == 2000 && failSecond) {
                failSecond = false;
                throw Exception('offline');
              }
              return PreviousEstimate(
                id: estimate.id ?? 'new-${++inserted}',
                propertyId: estimate.propertyId,
                priceEur: estimate.priceEur,
              );
            });
        final cubit = build(property: _answered)
          ..previouslyEstimatedChanged(previouslyEstimated: true)
          ..estimateAdded();
        final [first, second] = cubit.state.estimates;
        cubit
          ..estimateChanged(first.key, price: '1000')
          ..estimateChanged(second.key, price: '2000');

        await cubit.submit();
        expect(cubit.state.submission, PropertyContextSubmission.failure);
        expect(cubit.state.estimates.map((draft) => draft.id), ['new-1', null]);

        await cubit.submit();
        expect(cubit.state.submission, PropertyContextSubmission.success);
        expect(inserted, 2);
        expect(cubit.state.savedEstimates.map((e) => e.id), ['new-1', 'new-2']);
        final calls = verify(
          () => repository.savePreviousEstimate(captureAny()),
        ).captured.cast<PreviousEstimate>();
        // 1st insert, failed 2nd insert, then only the 2nd again.
        expect(calls.map((e) => (e.id, e.priceEur)), [
          (null, 1000),
          (null, 2000),
          (null, 2000),
        ]);
        await cubit.close();
      });

      test('emits nothing once closed', () async {
        final cubit = build(property: _answered, estimates: [_estimate]);
        when(() => repository.deletePreviousEstimate(any()))
            .thenAnswer((_) => cubit.close());
        final states = <PropertyContextState>[];
        final subscription = cubit.stream.listen(states.add);
        await cubit.submit();
        await subscription.cancel();
        expect(states.map((state) => state.submission), [
          PropertyContextSubmission.inProgress,
        ]);
      });

      test('reports no error once closed', () async {
        final cubit = build(property: _answered, estimates: [_estimate]);
        when(() => repository.deletePreviousEstimate(any()))
            .thenAnswer((_) async {
              await cubit.close();
              throw Exception('offline');
            });
        await expectLater(cubit.submit(), completes);
      });
    });
  });

  group('PropertyContextState', () {
    test('validates the purchase year', () {
      PropertyContextError? error(String year) =>
          _valid().copyWith(purchaseYear: year).purchaseYearError;
      expect(error(''), PropertyContextError.required);
      expect(error('1899'), PropertyContextError.yearRange);
      expect(error('2027'), PropertyContextError.yearRange);
      expect(error('1900'), isNull);
      expect(error('2026'), isNull);
    });

    test('validates the purchase price (optional)', () {
      PropertyContextError? error(String price) =>
          _valid().copyWith(purchasePrice: price).purchasePriceError;
      expect(error(''), isNull);
      expect(error('999'), PropertyContextError.amountRange);
      expect(error('100 000 001'), PropertyContextError.amountRange);
      expect(error('1 000'), isNull);
    });

    test('requires the property type and "Construit par vous ?"', () {
      final empty = PropertyContextState(today: _today);
      expect(empty.propertyTypeError, PropertyContextError.required);
      expect(empty.selfBuiltError, PropertyContextError.required);
      expect(empty.isValid, isFalse);
    });

    test('does not ask "Construit par vous ?" for a plot of land', () {
      final land = PropertyContextState(
        today: _today,
        propertyType: PropertyType.land,
        purchaseYear: '2000',
        selfBuilt: true,
      );
      expect(land.asksSelfBuilt, isFalse);
      expect(land.selfBuiltError, isNull);
      expect(land.isValid, isTrue);
      expect(land.patch[PropertyColumns.selfBuilt], isNull);
    });

    test('validates the estimates only when shown', () {
      const draft = EstimateDraft(key: 0, month: '13/2020');
      final state = _valid(previouslyEstimated: true, estimates: [draft]);
      expect(state.estimatePriceError(draft), PropertyContextError.required);
      expect(
        state.estimatePriceError(draft.copyWith(price: '10')),
        PropertyContextError.amountRange,
      );
      expect(state.estimateMonthError(draft), PropertyContextError.monthFormat);
      expect(state.isValid, isFalse);
      expect(state.copyWith(previouslyEstimated: false).isValid, isTrue);
      final fixed = draft.copyWith(price: '1 000', month: '');
      expect(state.copyWith(estimates: [fixed]).isValid, isTrue);
      expect(
        state.copyWith(estimates: [fixed.copyWith(month: '10/2026')]).isValid,
        isTrue,
      );
      expect(
        state.copyWith(estimates: [fixed.copyWith(month: '1/2020')]).isValid,
        isTrue,
      );
    });

    test('validates the month of an estimate', () {
      PropertyContextError? error(String month) =>
          _valid().estimateMonthError(EstimateDraft(key: 0, month: month));
      expect(error(' '), isNull);
      expect(error('05/2020'), isNull);
      expect(error('00/2020'), PropertyContextError.monthFormat);
      expect(error('05/1899'), PropertyContextError.monthTooEarly);
      expect(error('052020'), PropertyContextError.monthFormat);
      expect(error('11/2026'), PropertyContextError.monthFuture);
    });

    test('builds the patch of the step', () {
      final state = _valid(previouslyEstimated: true).copyWith(
        propertyType: PropertyType.other,
        propertyTypeOther: ' Local ',
        purchasePrice: '320\u00a0000',
        saleReason: () => SaleReason.relocation,
      );
      expect(state.patch, {
        PropertyColumns.propertyType: PropertyType.other,
        PropertyColumns.propertyTypeOther: 'Local',
        PropertyColumns.purchaseYear: 2012,
        PropertyColumns.purchasePriceEur: 320000,
        PropertyColumns.selfBuilt: false,
        PropertyColumns.saleReason: SaleReason.relocation,
        PropertyColumns.previouslyEstimated: true,
      });
      expect(
        state
            .copyWith(propertyTypeOther: ' ')
            .patch[PropertyColumns.propertyTypeOther],
        isNull,
      );
      expect(
        _valid()
            .copyWith(propertyTypeOther: 'Local')
            .patch[PropertyColumns.propertyTypeOther],
        isNull,
      );
    });
  });
}
