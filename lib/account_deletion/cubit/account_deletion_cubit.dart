import 'package:auth_repository/auth_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:profile_repository/profile_repository.dart';

part 'account_deletion_state.dart';

/// "Supprimer mon compte" (EPIC-11, US-11.9; owner decision 2026-10-03):
/// the account is deactivated at once, then deleted for good 30 days later
/// unless its user signs in again and reactivates it. Refused while a
/// property is on sale, and for a member of the Realesty team.
class AccountDeletionCubit extends Cubit<AccountDeletionState> {
  new({
    required this._profileRepository,
    required this._authRepository,
    this._timeout = const Duration(seconds: 15),
  }) : super(const AccountDeletionState());

  final ProfileRepository _profileRepository;
  final AuthRepository _authRepository;
  final Duration _timeout;

  /// Reads what prevents the deletion.
  Future<void> load() async {
    emit(state.copyWith(status: AccountDeletionStatus.loading));
    try {
      final blockers = await _profileRepository.getDeletionBlockers().timeout(
        _timeout,
      );
      if (isClosed) return;
      emit(
        state.copyWith(status: AccountDeletionStatus.ready, blockers: blockers),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: AccountDeletionStatus.loadFailure));
    }
  }

  /// The confirmation word typed by the user.
  void confirmationChanged(String value) =>
      emit(state.copyWith(confirmation: value, showErrors: false));

  /// Deactivates the account when [word] was typed ("SUPPRIMER").
  Future<void> deactivate(String word) async {
    if (state.status == AccountDeletionStatus.deactivating) return;
    if (state.confirmation.trim().toUpperCase() != word.toUpperCase()) {
      emit(state.copyWith(showErrors: true));
      return;
    }
    emit(state.copyWith(status: AccountDeletionStatus.deactivating));
    try {
      final due = await _profileRepository.deactivateAccount().timeout(
        _timeout,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          status: AccountDeletionStatus.deactivated,
          deletionDueAt: due,
        ),
      );
    } on AccountDeletionFailure catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      final blocker = error.blocker;
      emit(
        state.copyWith(
          status: blocker == null
              ? AccountDeletionStatus.deactivateFailure
              : AccountDeletionStatus.ready,
          blockers: {...state.blockers, ?blocker},
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: AccountDeletionStatus.deactivateFailure));
    }
  }

  /// Signs out of every device once the account is deactivated (the app
  /// then goes back to the sign-in screen).
  Future<void> finish() async {
    try {
      await _authRepository.signOut(everywhere: true);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      try {
        await _authRepository.signOut();
      } on Object catch (error, stackTrace) {
        addError(error, stackTrace);
      }
    }
  }
}
