part of 'app_bloc.dart';

sealed class AppEvent {
  const new();
}

/// Starts listening to the signed-in user. Add it once, at startup.
final class AppUserSubscriptionRequested extends AppEvent {
  const new();
}

/// The user asked to sign out.
final class AppLogoutPressed extends AppEvent {
  const new();
}
