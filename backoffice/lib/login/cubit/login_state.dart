part of 'login_cubit.dart';

enum LoginStatus {
  idle,
  invalidEmail,
  sending,
  sent,
  rateLimited,
  failure,
  passwordFailure,
}

class LoginState extends Equatable {
  const new({
    this.email = '',
    this.password = '',
    this.status = LoginStatus.idle,
  });

  final String email;
  final String password;
  final LoginStatus status;

  bool get isSending => status == LoginStatus.sending;

  LoginState copyWith({LoginStatus? status}) => LoginState(
    email: email,
    password: password,
    status: status ?? this.status,
  );

  @override
  List<Object?> get props => [email, password, status];
}
