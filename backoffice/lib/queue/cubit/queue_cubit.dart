import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'queue_state.dart';

/// Rows of the queue, grouped so that the dossiers of a lot follow each
/// other (at the place of the oldest one).
List<DossierSummary> groupByLot(List<DossierSummary> rows) {
  final firstIndex = <String, int>{};
  for (var i = 0; i < rows.length; i++) {
    final lot = rows[i].lot?.id;
    if (lot != null) firstIndex.putIfAbsent(lot, () => i);
  }
  final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])]
    ..sort((a, b) {
      final ka = a.$2.lot == null ? a.$1 : firstIndex[a.$2.lot!.id]!;
      final kb = b.$2.lot == null ? b.$1 : firstIndex[b.$2.lot!.id]!;
      return ka != kb ? ka.compareTo(kb) : a.$1.compareTo(b.$1);
    });
  return [for (final (_, row) in indexed) row];
}

class QueueCubit extends Cubit<QueueState> {
  new({required this._repository, this.pageSize = 100})
    : super(const QueueState());

  final BackOfficeRepository _repository;
  final int pageSize;

  Future<List<DossierSummary>> _fetch(int offset) => _repository.listDossiers(
    statuses: state.filter.statuses,
    scope: state.scope,
    search: state.search.trim().isEmpty ? null : state.search.trim(),
    limit: pageSize,
    offset: offset,
  );

  Future<void> load() async {
    emit(state.copyWith(status: QueueStatus.loading));
    try {
      final rows = await _fetch(0);
      emit(
        state.copyWith(
          status: QueueStatus.ready,
          rows: groupByLot(rows),
          hasMore: rows.length == pageSize,
        ),
      );
    } on Object {
      emit(state.copyWith(status: QueueStatus.failure, rows: const []));
      rethrow;
    }
  }

  Future<void> loadMore() async {
    final more = await _fetch(state.rows.length);
    emit(
      state.copyWith(
        rows: groupByLot([...state.rows, ...more]),
        hasMore: more.length == pageSize,
      ),
    );
  }

  Future<void> setFilter(QueueFilter filter) {
    emit(state.copyWith(filter: filter));
    return load();
  }

  Future<void> setScope(DossierScope scope) {
    emit(state.copyWith(scope: scope));
    return load();
  }

  Future<void> setSearch(String search) {
    emit(state.copyWith(search: search));
    return load();
  }

  Future<void> _rowAction(String id, Future<void> Function() action) async {
    emit(state.copyWith(busyId: () => id));
    try {
      await action();
      await load();
    } finally {
      emit(state.copyWith(busyId: () => null));
    }
  }

  /// « Prendre en charge ».
  Future<void> startReview(String id) =>
      _rowAction(id, () => _repository.startReview(id));

  Future<void> assign(String id, String userId, {String? note}) =>
      _rowAction(id, () => _repository.assign(id, userId, note: note));

  Future<void> unassign(String id) =>
      _rowAction(id, () => _repository.unassign(id));

  /// Admin: active members for the assignment dialog.
  Future<void> loadTeam() async {
    final team = await _repository.listTeam();
    emit(
      state.copyWith(
        team: [
          for (final m in team)
            if (m.active) m,
        ],
      ),
    );
  }
}
