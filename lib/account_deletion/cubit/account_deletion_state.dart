part of 'account_deletion_cubit.dart';

enum AccountDeletionStatus {
  initial,
  loading,
  loadFailure,
  ready,
  deactivating,
  deactivateFailure,
  deactivated,
}

final class AccountDeletionState extends Equatable {
  const new({
    this.status = AccountDeletionStatus.initial,
    this.blockers = const {},
    this.confirmation = '',
    this.showErrors = false,
    this.deletionDueAt,
  });

  final AccountDeletionStatus status;

  /// What prevents the deletion (a sale in progress, a team account).
  final Set<AccountDeletionBlocker> blockers;

  /// The confirmation word typed.
  final String confirmation;

  /// The confirmation was submitted without the right word.
  final bool showErrors;

  /// When the deactivated account is deleted for good.
  final DateTime? deletionDueAt;

  bool get isBlocked => blockers.isNotEmpty;

  AccountDeletionState copyWith({
    AccountDeletionStatus? status,
    Set<AccountDeletionBlocker>? blockers,
    String? confirmation,
    bool? showErrors,
    DateTime? deletionDueAt,
  }) => AccountDeletionState(
    status: status ?? this.status,
    blockers: blockers ?? this.blockers,
    confirmation: confirmation ?? this.confirmation,
    showErrors: showErrors ?? this.showErrors,
    deletionDueAt: deletionDueAt ?? this.deletionDueAt,
  );

  @override
  List<Object?> get props => [
    status,
    blockers,
    confirmation,
    showErrors,
    deletionDueAt,
  ];
}
