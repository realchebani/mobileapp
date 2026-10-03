import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/queue/queue.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

void main() {
  late MockBackOfficeRepository repository;

  void stubList(List<DossierSummary> rows) => when(
    () => repository.listDossiers(
      statuses: any(named: 'statuses'),
      scope: any(named: 'scope'),
      search: any(named: 'search'),
      limit: any(named: 'limit'),
      offset: any(named: 'offset'),
    ),
  ).thenAnswer((_) async => rows);

  setUp(() {
    repository = MockBackOfficeRepository();
    stubList([summary()]);
    when(() => repository.startReview(any())).thenAnswer((_) async {});
    when(() => repository.assign(any(), any(), note: any(named: 'note')))
        .thenAnswer((_) async {});
    when(() => repository.unassign(any())).thenAnswer((_) async {});
    when(() => repository.listTeam()).thenAnswer((_) async => team);
  });

  test('groupByLot keeps the members of a lot together', () {
    const lot = LotRef(id: 'l1', name: 'Lot');
    final rows = groupByLot([
      summary(id: 'a', lot: lot),
      summary(id: 'b'),
      summary(id: 'c', lot: lot),
      summary(id: 'd'),
    ]);
    expect(rows.map((r) => r.id), ['a', 'c', 'b', 'd']);
  });

  blocTest<QueueCubit, QueueState>(
    'loads with the filters',
    build: () => QueueCubit(repository: repository, pageSize: 1),
    act: (cubit) async {
      await cubit.setFilter(QueueFilter.certified);
      await cubit.setScope(DossierScope.mine);
      await cubit.setSearch(' Chap ');
      await cubit.setSearch(' ');
    },
    verify: (cubit) {
      expect(cubit.state.hasMore, isTrue);
      verify(
        () => repository.listDossiers(
          statuses: [DossierStatus.certified],
          scope: DossierScope.mine,
          search: 'Chap',
          limit: 1,
        ),
      ).called(1);
      verify(
        () => repository.listDossiers(
          statuses: [DossierStatus.certified],
          scope: DossierScope.mine,
          limit: 1,
        ),
      ).called(2);
    },
  );

  blocTest<QueueCubit, QueueState>(
    'load more appends',
    build: () => QueueCubit(repository: repository, pageSize: 1),
    seed: () => QueueState(status: QueueStatus.ready, rows: [summary()]),
    act: (cubit) {
      stubList([summary(id: 'p2')]);
      return cubit.loadMore();
    },
    verify: (cubit) {
      expect(cubit.state.rows.map((r) => r.id), ['p1', 'p2']);
      verify(
        () => repository.listDossiers(
          statuses: QueueFilter.open.statuses,
          limit: 1,
          offset: 1,
        ),
      ).called(1);
    },
  );

  blocTest<QueueCubit, QueueState>(
    'a failed load',
    setUp: () => when(
      () => repository.listDossiers(
        statuses: any(named: 'statuses'),
        scope: any(named: 'scope'),
        search: any(named: 'search'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenThrow(Exception('x')),
    build: () => QueueCubit(repository: repository),
    act: (cubit) => cubit.load(),
    errors: () => [isA<Exception>()],
    expect: () => [
      const QueueState(),
      const QueueState(status: QueueStatus.failure),
    ],
  );

  blocTest<QueueCubit, QueueState>(
    'row actions reload and clear the busy row, even on failure',
    build: () => QueueCubit(repository: repository),
    act: (cubit) async {
      await cubit.startReview('p1');
      await cubit.assign('p1', 'expert-1', note: 'Urgent');
      await cubit.unassign('p1');
      when(() => repository.startReview(any())).thenThrow(Exception('x'));
      await expectLater(cubit.startReview('p1'), throwsException);
      await cubit.loadTeam();
    },
    verify: (cubit) {
      expect(cubit.state.busyId, isNull);
      expect(cubit.state.team.map((m) => m.userId), ['expert-1', 'partner-1']);
      verify(() => repository.assign('p1', 'expert-1', note: 'Urgent'))
          .called(1);
      verify(() => repository.unassign('p1')).called(1);
    },
  );
}
