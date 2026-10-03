import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthState;

part 'session_state.dart';

/// Where the signed-in user stands: signed out → TOTP code → member.
/// Every `bo_*` call re-checks the role and MFA in the database; this cubit
/// only decides which screen to show.
class SessionCubit extends Cubit<SessionState> {
  new({required this._auth, required this._repository})
    : super(const SessionState()) {
    _subscription = _auth.changes.listen((change) {
      if (change.event != AuthChangeEvent.tokenRefreshed) unawaited(refresh());
    });
  }

  final BackOfficeAuthRepository _auth;
  final BackOfficeRepository _repository;
  late final StreamSubscription<AuthState> _subscription;

  Future<void> refresh() async {
    if (!_auth.isSignedIn) {
      emit(const SessionState(status: SessionStatus.signedOut));
      return;
    }
    try {
      final mfa = await _auth.mfaStatus();
      if (!mfa.passed) {
        emit(SessionState(status: SessionStatus.mfa, mfa: mfa));
        return;
      }
      final me = await _repository.me();
      emit(
        SessionState(
          status: me.isMember ? SessionStatus.ready : SessionStatus.denied,
          me: me,
          mfa: mfa,
        ),
      );
    } on Object {
      emit(const SessionState(status: SessionStatus.failed));
    }
  }

  /// A call was refused because the access changed (deactivated, MFA
  /// lost): show the right screen.
  void onFailure(Object error) {
    if (error is! BackOfficeFailure) return;
    switch (error.reason) {
      case BackOfficeFailureReason.notStaff:
      case BackOfficeFailureReason.mfaRequired:
      case BackOfficeFailureReason.notAuthenticated:
        unawaited(refresh());
      case _:
        return;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Object {
      // Signed out locally anyway.
    }
    emit(const SessionState(status: SessionStatus.signedOut));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await super.close();
  }
}
