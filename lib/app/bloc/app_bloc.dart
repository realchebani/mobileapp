import 'package:auth_repository/auth_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

part 'app_event.dart';
part 'app_state.dart';

/// Tracks whether a user is signed in, from the auth repository.
class AppBloc extends Bloc<AppEvent, AppState> {
  new({required this._authRepository}) : super(const AppState()) {
    on<AppUserSubscriptionRequested>(_onUserSubscriptionRequested);
    on<AppLogoutPressed>(_onLogoutPressed);
  }

  final AuthRepository _authRepository;

  Future<void> _onUserSubscriptionRequested(
    AppUserSubscriptionRequested event,
    Emitter<AppState> emit,
  ) {
    return emit.onEach(
      _authRepository.user,
      onData: (user) => emit(
        user == null
            ? const AppState.unauthenticated()
            : AppState.authenticated(user),
      ),
      onError: addError,
    );
  }

  Future<void> _onLogoutPressed(
    AppLogoutPressed event,
    Emitter<AppState> emit,
  ) async {
    try {
      await _authRepository.signOut();
    } on SignOutFailure catch (error, stackTrace) {
      addError(error, stackTrace);
    }
  }
}
