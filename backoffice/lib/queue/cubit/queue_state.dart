part of 'queue_cubit.dart';

/// Status filter of the queue.
enum QueueFilter {
  open([DossierStatus.submitted, DossierStatus.inReview]),
  submitted([DossierStatus.submitted]),
  inReview([DossierStatus.inReview]),
  certified([DossierStatus.certified]),
  all(null);

  new(this.statuses);

  final List<DossierStatus>? statuses;
}

enum QueueStatus { loading, ready, failure }

class QueueState extends Equatable {
  const new({
    this.status = QueueStatus.loading,
    this.rows = const [],
    this.filter = QueueFilter.open,
    this.scope = DossierScope.all,
    this.search = '',
    this.hasMore = false,
    this.team = const [],
    this.busyId,
  });

  final QueueStatus status;
  final List<DossierSummary> rows;
  final QueueFilter filter;
  final DossierScope scope;
  final String search;
  final bool hasMore;

  /// Active members, for the assignment dialog (admin).
  final List<StaffMember> team;

  /// Dossier whose row action is running.
  final String? busyId;

  QueueState copyWith({
    QueueStatus? status,
    List<DossierSummary>? rows,
    QueueFilter? filter,
    DossierScope? scope,
    String? search,
    bool? hasMore,
    List<StaffMember>? team,
    String? Function()? busyId,
  }) => QueueState(
    status: status ?? this.status,
    rows: rows ?? this.rows,
    filter: filter ?? this.filter,
    scope: scope ?? this.scope,
    search: search ?? this.search,
    hasMore: hasMore ?? this.hasMore,
    team: team ?? this.team,
    busyId: busyId == null ? this.busyId : busyId(),
  );

  @override
  List<Object?> get props => [
    status,
    rows,
    filter,
    scope,
    search,
    hasMore,
    team,
    busyId,
  ];
}
