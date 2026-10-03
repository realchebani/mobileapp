import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'mfa_state.dart';

/// Enrols a TOTP factor (first sign-in) or checks the code.
class MfaCubit extends Cubit<MfaState> {
  new({required this._auth, required String? factorId})
    : super(MfaState(factorId: factorId));

  final BackOfficeAuthRepository _auth;

  /// Starts the enrolment when there is no verified factor yet.
  Future<void> start() async {
    if (state.factorId != null) return;
    emit(state.copyWith(status: MfaStatusValue.loading));
    try {
      final enrollment = await _auth.enrollTotp();
      emit(
        MfaState(
          factorId: enrollment.factorId,
          enrollment: enrollment,
          code: state.code,
        ),
      );
    } on BackOfficeAuthFailure {
      emit(state.copyWith(status: MfaStatusValue.failure));
    }
  }

  void codeChanged(String code) =>
      emit(state.copyWith(code: code, status: MfaStatusValue.idle));

  /// Checks the code; the session moves on through the auth stream.
  Future<bool> verify() async {
    final factorId = state.factorId;
    if (factorId == null) return false;
    if (!RegExp(r'^\d{6}$').hasMatch(state.code.trim())) {
      emit(state.copyWith(status: MfaStatusValue.invalidCode));
      return false;
    }
    emit(state.copyWith(status: MfaStatusValue.verifying));
    try {
      await _auth.verifyTotp(factorId, state.code);
      emit(state.copyWith(status: MfaStatusValue.verified));
      return true;
    } on BackOfficeAuthFailure catch (failure) {
      emit(
        state.copyWith(
          status: failure.reason == BackOfficeAuthFailureReason.invalidCode
              ? MfaStatusValue.invalidCode
              : MfaStatusValue.failure,
        ),
      );
      return false;
    }
  }
}
