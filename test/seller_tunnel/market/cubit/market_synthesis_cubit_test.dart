import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/market/cubit/market_synthesis_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

void main() {
  late MockPropertyRepository repository;
  final ok = MarketSnapshot(
    id: 's',
    propertyId: 'p',
    status: MarketSnapshotStatus.ok,
    createdAt: DateTime(2026, 10),
  );

  setUp(() => repository = MockPropertyRepository());

  MarketSynthesisCubit build() =>
      MarketSynthesisCubit(propertyRepository: repository, propertyId: 'p');

  test('starts loading', () {
    expect(build().state, const MarketSynthesisState());
  });

  blocTest<MarketSynthesisCubit, MarketSynthesisState>(
    'ready with an ok snapshot',
    setUp: () =>
        when(() => repository.getMarketSnapshot('p'))
            .thenAnswer((_) async => ok),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      const MarketSynthesisState(),
      MarketSynthesisState(status: MarketSynthesisStatus.ready, snapshot: ok),
    ],
  );

  blocTest<MarketSynthesisCubit, MarketSynthesisState>(
    'unavailable without an ok snapshot',
    setUp: () =>
        when(() => repository.getMarketSnapshot('p'))
            .thenAnswer((_) async => null),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      const MarketSynthesisState(),
      const MarketSynthesisState(status: MarketSynthesisStatus.unavailable),
    ],
  );

  blocTest<MarketSynthesisCubit, MarketSynthesisState>(
    'failure',
    setUp: () =>
        when(() => repository.getMarketSnapshot('p'))
            .thenThrow(const PropertyLoadFailure('x')),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      const MarketSynthesisState(),
      const MarketSynthesisState(status: MarketSynthesisStatus.failure),
    ],
    errors: () => [isA<PropertyLoadFailure>()],
  );

  test('does not emit once closed', () async {
    when(() => repository.getMarketSnapshot('p')).thenAnswer((_) async => ok);
    final cubit = build();
    final loading = cubit.load();
    await cubit.close();
    await loading;
    when(() => repository.getMarketSnapshot('p'))
        .thenAnswer((_) async => throw const PropertyLoadFailure('x'));
    final failing = build();
    final failingLoad = failing.load();
    await failing.close();
    await failingLoad;
    expect(failing.state, const MarketSynthesisState());
  });
}
