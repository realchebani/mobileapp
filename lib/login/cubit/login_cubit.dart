import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/login/cubit/ticker.dart';

part 'login_state.dart';

/// Magic-link login: e-mail entry, sending the link, and resending it.
class LoginCubit extends Cubit<LoginState> {
  new({required this._authRepository, this._ticker = const Ticker()})
    : super(const LoginState()) {
    _linkFailureSubscription = _authRepository.linkFailures.listen(
      _onLinkFailure,
    );
  }

  /// Delay before a link can be sent again.
  static const resendDelay = 60;

  final AuthRepository _authRepository;
  final Ticker _ticker;
  StreamSubscription<int>? _tickerSubscription;
  late final StreamSubscription<AuthLinkFailure> _linkFailureSubscription;

  /// Bumped by [editEmail] so that in-flight sends are ignored.
  int _attempt = 0;

  void emailChanged(String email) {
    emit(
      state.copyWith(
        email: email,
        status: state.status == LoginStatus.failure
            ? LoginStatus.initial
            : null,
        failureReason: () => null,
      ),
    );
  }

  void termsToggled() {
    emit(state.copyWith(termsAccepted: !state.termsAccepted));
  }

  /// Sends the magic link to the entered e-mail.
  void submit() {
    if (!state.canSubmit) return;
    unawaited(_send(state.email.trim()));
  }

  /// Sends the magic link again to the address it was last sent to.
  void resend() {
    final sentTo = state.sentTo;
    if (sentTo == null || !state.canResend) return;
    unawaited(_send(sentTo));
  }

  /// Goes back to e-mail entry, keeping the entered e-mail.
  void editEmail() {
    _attempt++;
    unawaited(_tickerSubscription?.cancel());
    _tickerSubscription = null;
    emit(
      state.copyWith(
        status: LoginStatus.initial,
        failureReason: () => null,
        sentTo: () => null,
        resendAvailableIn: 0,
      ),
    );
  }

  /// Forgets everything (e-mail, terms, sent link), e.g. on sign-out.
  void reset() {
    _attempt++;
    unawaited(_tickerSubscription?.cancel());
    _tickerSubscription = null;
    emit(const LoginState());
  }

  Future<void> _send(String email) async {
    final attempt = _attempt;
    emit(
      state.copyWith(status: LoginStatus.submitting, failureReason: () => null),
    );
    try {
      await _authRepository.sendMagicLink(email: email);
    } on Object catch (error, stackTrace) {
      if (isClosed || attempt != _attempt) return;
      final reason = error is SendMagicLinkFailure
          ? _toLoginReason(error.reason)
          : LoginFailureReason.unknown;
      if (error is! SendMagicLinkFailure) addError(error, stackTrace);
      final restartCountdown =
          reason == LoginFailureReason.rateLimited && state.sentTo != null;
      emit(
        state.copyWith(
          status: LoginStatus.failure,
          failureReason: () => reason,
          resendAvailableIn: restartCountdown ? resendDelay : null,
        ),
      );
      if (restartCountdown) _startCountdown();
      return;
    }
    if (isClosed || attempt != _attempt) return;
    emit(
      state.copyWith(
        status: LoginStatus.sent,
        sentTo: () => email,
        resendAvailableIn: resendDelay,
      ),
    );
    _startCountdown();
  }

  /// A magic link failed to sign in. Reported whatever the step, including
  /// on a cold start from an expired link (the cubit lives at the app
  /// level and subscribes at startup).
  void _onLinkFailure(AuthLinkFailure failure) {
    emit(
      state.copyWith(
        status: LoginStatus.failure,
        failureReason: () => failure.reason == AuthLinkFailureReason.expired
            ? LoginFailureReason.linkExpired
            : LoginFailureReason.linkInvalid,
      ),
    );
  }

  static LoginFailureReason _toLoginReason(
    SendMagicLinkFailureReason reason,
  ) => switch (reason) {
    SendMagicLinkFailureReason.invalidEmail => LoginFailureReason.invalidEmail,
    SendMagicLinkFailureReason.notAuthorized =>
      LoginFailureReason.notAuthorized,
    SendMagicLinkFailureReason.rateLimited => LoginFailureReason.rateLimited,
    SendMagicLinkFailureReason.network => LoginFailureReason.network,
    SendMagicLinkFailureReason.unknown => LoginFailureReason.unknown,
  };

  void _startCountdown() {
    unawaited(_tickerSubscription?.cancel());
    _tickerSubscription = _ticker
        .tick(ticks: resendDelay)
        .listen(
          (remaining) => emit(state.copyWith(resendAvailableIn: remaining)),
        );
  }

  @override
  Future<void> close() async {
    await _tickerSubscription?.cancel();
    await _linkFailureSubscription.cancel();
    await super.close();
  }
}
