import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';

void main() {
  late ValuationRepository repository;

  setUp(() => repository = MockValuationRepository());

  ValuationCubit build() => ValuationCubit(
    valuationRepository: repository,
    timeout: const Duration(seconds: 1),
  );

  test('initial state', () {
    expect(
      ValuationCubit(valuationRepository: repository).state,
      const ValuationState(),
    );
  });

  blocTest<ValuationCubit, ValuationState>(
    'loads the latest valuation',
    setUp: () =>
        when(() => repository.getLatestValuation(any()))
            .thenAnswer((_) async => testValuation),
    build: build,
    act: (cubit) => cubit.load('property-id'),
    expect: () => [
      const ValuationState(status: ValuationStatus.loading),
      ValuationState(status: ValuationStatus.success, valuation: testValuation),
    ],
    verify: (_) =>
        verify(() => repository.getLatestValuation('property-id')).called(1),
  );

  blocTest<ValuationCubit, ValuationState>(
    'keeps the valuation when loading fails',
    setUp: () =>
        when(() => repository.getLatestValuation(any()))
            .thenThrow(const ValuationLoadFailure()),
    build: build,
    seed: () => ValuationState(
      status: ValuationStatus.success,
      valuation: testValuation,
    ),
    act: (cubit) => cubit.load('property-id'),
    expect: () => [
      ValuationState(status: ValuationStatus.loading, valuation: testValuation),
      ValuationState(status: ValuationStatus.failure, valuation: testValuation),
    ],
    errors: () => [isA<ValuationLoadFailure>()],
  );

  blocTest<ValuationCubit, ValuationState>(
    'ignores a load while loading',
    build: build,
    seed: () => const ValuationState(status: ValuationStatus.loading),
    act: (cubit) => cubit.load('property-id'),
    expect: () => const <ValuationState>[],
  );

  test('ignores answers arriving after close', () async {
    final success = Completer<Valuation?>();
    when(() => repository.getLatestValuation('a'))
        .thenAnswer((_) => success.future);
    final failure = Completer<Valuation?>();
    when(() => repository.getLatestValuation('b'))
        .thenAnswer((_) => failure.future);

    final first = build();
    final loadingA = first.load('a');
    await first.close();
    success.complete(testValuation);
    await loadingA;
    expect(first.state.status, ValuationStatus.loading);

    final second = build();
    final loadingB = second.load('b');
    await second.close();
    failure.completeError(const ValuationLoadFailure());
    await loadingB;
    expect(second.state.status, ValuationStatus.loading);
  });
}
