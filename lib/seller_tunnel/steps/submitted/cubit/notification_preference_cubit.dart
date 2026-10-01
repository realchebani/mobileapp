import 'package:bloc/bloc.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/data/notification_preference_store.dart';

/// Saves the choice in the dossier (`notify_push`); answers whether it
/// was saved.
typedef RemoteNotificationSave = Future<bool> Function({required bool enabled});

/// Whether the seller wants to be notified when the certified valuation is
/// available (V8 switch).
///
/// The choice is kept in a [NotificationPreferenceStore] (the source while
/// the dossier is locked) and, when a remote save is given (dossier still
/// open), also written to the dossier; a failed remote write reverts it.
/// Starts from the dossier value until [load] reads the saved choice.
class NotificationPreferenceCubit extends Cubit<bool> {
  new({
    required this._store,
    required this._propertyId,
    required bool initialValue,
    this._saveRemote,
  }) : super(initialValue);

  final NotificationPreferenceStore _store;
  final String _propertyId;
  final RemoteNotificationSave? _saveRemote;

  /// Whether the user changed the choice (then [load] keeps it).
  bool _changed = false;

  /// Reads the saved choice (kept unchanged if none, unreadable or already
  /// changed by the user).
  Future<void> load() async {
    try {
      final saved = await _store.read(_propertyId);
      if (saved != null && !_changed && !isClosed) emit(saved);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
    }
  }

  /// Turns the notifications on or off and saves the choice.
  Future<void> toggled({required bool enabled}) async {
    _changed = true;
    emit(enabled);
    final saveRemote = _saveRemote;
    if (saveRemote != null && !await saveRemote(enabled: enabled)) {
      if (!isClosed) emit(!enabled);
      return;
    }
    try {
      await _store.write(_propertyId, enabled: enabled);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
    }
  }
}
