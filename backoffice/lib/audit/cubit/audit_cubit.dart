import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

enum AuditStatus { loading, ready, failure }

/// Filters of the journal.
class AuditFilters extends Equatable {
  const new({
    this.actorUserId,
    this.action,
    this.propertyId,
    this.since,
    this.until,
  });

  final String? actorUserId;
  final String? action;
  final String? propertyId;
  final DateTime? since;

  /// Inclusive day: entries before the next midnight.
  final DateTime? until;

  @override
  List<Object?> get props => [actorUserId, action, propertyId, since, until];
}

class AuditState extends Equatable {
  const new({
    this.status = AuditStatus.loading,
    this.entries = const [],
    this.filters = const AuditFilters(),
    this.team = const [],
  });

  final AuditStatus status;
  final List<AuditEntry> entries;
  final AuditFilters filters;

  /// Members, for the person filter.
  final List<StaffMember> team;

  AuditState copyWith({
    AuditStatus? status,
    List<AuditEntry>? entries,
    AuditFilters? filters,
    List<StaffMember>? team,
  }) => AuditState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    filters: filters ?? this.filters,
    team: team ?? this.team,
  );

  @override
  List<Object?> get props => [status, entries, filters, team];
}

/// Admin: the whole journal, filtered, exported as CSV.
class AuditCubit extends Cubit<AuditState> {
  new({required this._repository}) : super(const AuditState());

  final BackOfficeRepository _repository;

  /// Lines shown and exported at most.
  static const limit = 1000;

  Future<void> load([AuditFilters? filters]) async {
    final f = filters ?? state.filters;
    emit(state.copyWith(status: AuditStatus.loading, filters: f));
    try {
      final entries = await _repository.audit(
        propertyId: f.propertyId,
        actorUserId: f.actorUserId,
        action: f.action,
        since: f.since,
        until: f.until?.add(const Duration(days: 1)),
        limit: limit,
      );
      emit(state.copyWith(status: AuditStatus.ready, entries: entries));
    } on Object {
      emit(state.copyWith(status: AuditStatus.failure));
      rethrow;
    }
  }

  Future<void> loadTeam() async {
    final team = await _repository.listTeam();
    emit(state.copyWith(team: team));
  }
}
