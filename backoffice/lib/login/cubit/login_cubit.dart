import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'login_state.dart';

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class LoginCubit extends Cubit<LoginState> {
  new({required this._auth, required this._redirectUrl})
    : super(const LoginState());

  final BackOfficeAuthRepository _auth;
  final String _redirectUrl;

  void emailChanged(String value) =>
      emit(LoginState(email: value, password: state.password));

  void passwordChanged(String value) =>
      emit(LoginState(email: state.email, password: value));

  Future<void> sendLink() async {
    if (!_email.hasMatch(state.email.trim())) {
      emit(state.copyWith(status: LoginStatus.invalidEmail));
      return;
    }
    emit(state.copyWith(status: LoginStatus.sending));
    try {
      await _auth.sendMagicLink(state.email, redirectTo: _redirectUrl);
      emit(state.copyWith(status: LoginStatus.sent));
    } on BackOfficeAuthFailure catch (failure) {
      emit(
        state.copyWith(
          status: failure.reason == BackOfficeAuthFailureReason.rateLimited
              ? LoginStatus.rateLimited
              : LoginStatus.failure,
        ),
      );
    }
  }

  /// Development only: a test account with a password.
  Future<void> signInWithPassword() async {
    emit(state.copyWith(status: LoginStatus.sending));
    try {
      await _auth.signInWithPassword(state.email, state.password);
      emit(state.copyWith(status: LoginStatus.idle));
    } on BackOfficeAuthFailure {
      emit(state.copyWith(status: LoginStatus.passwordFailure));
    }
  }

  void restart() => emit(LoginState(email: state.email));
}
