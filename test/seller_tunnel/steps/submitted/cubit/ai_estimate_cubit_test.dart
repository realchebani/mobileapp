import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/cubit/ai_estimate_cubit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

final _now = DateTime(2026, 10, 1, 12);

MarketSnapshot _snapshot(MarketSnapshotStatus status, {DateTime? createdAt}) =>
    MarketSnapshot(
      id: 's',
      propertyId: 'p',
      status: status,
      createdAt: createdAt ?? _now,
    );

void main() {
  late MockPropertyRepository repository;

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.requestEstimate(any())).thenAnswer((_) async {});
  });

  AiEstimateCubit build({bool enabled = true, int maxPolls = 3}) =>
      AiEstimateCubit(
        propertyRepository: repository,
        propertyId: 'p',
        enabled: enabled,
        pollInterval: Duration.zero,
        maxPolls: maxPolls,
        now: () => _now,
      );

  void answers(List<Object?> values) {
    when(() => repository.getMarketSnapshot('p')).thenAnswer((_) async {
      final value = values.length > 1 ? values.removeAt(0) : values.first;
      if (value is Exception) throw value;
      return value as MarketSnapshot?;
    });
  }

  const computing = AiEstimateState(status: AiEstimateStatus.computing);
  const failed = AiEstimateState(status: AiEstimateStatus.failed);

  test('starts hidden', () {
    expect(build().state, const AiEstimateState());
  });

  blocTest<AiEstimateCubit, AiEstimateState>(
    'stays hidden when disabled',
    build: () => build(enabled: false),
    act: (cubit) => cubit.load(),
    expect: () => <AiEstimateState>[],
    verify: (_) => verifyNever(() => repository.getMarketSnapshot(any())),
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'shows a definitive result',
    setUp: () => answers([_snapshot(MarketSnapshotStatus.ok)]),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      computing,
      AiEstimateState(
        status: AiEstimateStatus.ready,
        snapshot: _snapshot(MarketSnapshotStatus.ok),
      ),
    ],
    verify: (_) => verifyNever(() => repository.requestEstimate(any())),
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'no estimate for the property',
    setUp: () => answers([_snapshot(MarketSnapshotStatus.insufficient)]),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [
      computing,
      AiEstimateState(
        status: AiEstimateStatus.unavailable,
        snapshot: _snapshot(MarketSnapshotStatus.insufficient),
      ),
    ],
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'requests it when there was no attempt, then polls until ready',
    setUp: () => answers([
      null,
      null,
      Exception('offline'),
      _snapshot(MarketSnapshotStatus.running),
      _snapshot(MarketSnapshotStatus.ok),
    ]),
    build: () => build(maxPolls: 10),
    act: (cubit) => cubit.load(),
    expect: () => [
      computing,
      AiEstimateState(
        status: AiEstimateStatus.ready,
        snapshot: _snapshot(MarketSnapshotStatus.ok),
      ),
    ],
    errors: () => [isA<Exception>()],
    verify: (_) => verify(() => repository.requestEstimate('p')).called(1),
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'fails when polling never ends',
    setUp: () => answers([_snapshot(MarketSnapshotStatus.running)]),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [computing, failed],
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'a dead computation or a failed one is a failure',
    setUp: () => answers([
      _snapshot(
        MarketSnapshotStatus.running,
        createdAt: _now.subtract(const Duration(minutes: 10)),
      ),
    ]),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [computing, failed],
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'reading failure',
    setUp: () => answers([Exception('offline')]),
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [computing, failed],
    errors: () => [isA<Exception>()],
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'request failure',
    setUp: () {
      answers([null]);
      when(() => repository.requestEstimate(any()))
          .thenThrow(const EstimateRequestFailure('x'));
    },
    build: build,
    act: (cubit) => cubit.load(),
    expect: () => [computing, failed],
    errors: () => [isA<EstimateRequestFailure>()],
  );

  blocTest<AiEstimateCubit, AiEstimateState>(
    'retry requests the estimate again after a failure only',
    setUp: () => answers([
      _snapshot(MarketSnapshotStatus.error),
      _snapshot(MarketSnapshotStatus.ok),
    ]),
    build: build,
    act: (cubit) async {
      await cubit.retry();
      await cubit.load();
      await cubit.retry();
    },
    expect: () => [
      computing,
      failed,
      computing,
      AiEstimateState(
        status: AiEstimateStatus.ready,
        snapshot: _snapshot(MarketSnapshotStatus.ok),
      ),
    ],
    verify: (_) => verify(() => repository.requestEstimate('p')).called(1),
  );

  test('stops polling once closed', () async {
    answers([_snapshot(MarketSnapshotStatus.running)]);
    final cubit = AiEstimateCubit(
      propertyRepository: repository,
      propertyId: 'p',
      enabled: true,
      pollInterval: const Duration(milliseconds: 10),
      now: () => _now,
    );
    final loading = cubit.load();
    await cubit.close();
    await loading;
    expect(cubit.state, computing);
  });

  test('defaults its clock and polling', () {
    expect(
      AiEstimateCubit(
        propertyRepository: repository,
        propertyId: 'p',
        enabled: false,
      ).state,
      const AiEstimateState(),
    );
  });
}
