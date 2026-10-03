import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:profile_repository/profile_repository.dart';

part 'profile_form_state.dart';

/// V19 · the personal information of the user being edited: validated,
/// then saved with a timeout. The dossiers' owners are not changed (they
/// are independent of the profile).
class ProfileFormCubit extends Cubit<ProfileFormState> {
  new({
    required this._profileRepository,
    required Profile profile,
    this._timeout = const Duration(seconds: 15),
  }) : super(ProfileFormState.of(profile));

  final ProfileRepository _profileRepository;
  final Duration _timeout;

  void firstNameChanged(String value) =>
      emit(state.copyWith(firstName: value, status: ProfileFormStatus.editing));

  void lastNameChanged(String value) =>
      emit(state.copyWith(lastName: value, status: ProfileFormStatus.editing));

  void phoneChanged(String value) =>
      emit(state.copyWith(phone: value, status: ProfileFormStatus.editing));

  void postalAddressChanged(String value) => emit(
    state.copyWith(postalAddress: value, status: ProfileFormStatus.editing),
  );

  /// Saves the information (status saved, with the saved profile), or
  /// shows the errors, or reports a failure.
  Future<void> save() async {
    if (state.status == ProfileFormStatus.saving) return;
    if (!state.isValid) {
      emit(state.copyWith(showErrors: true));
      return;
    }
    emit(state.copyWith(status: ProfileFormStatus.saving));
    try {
      final profile = await _profileRepository
          .updateDetails(state.profile.id, state.details)
          .timeout(_timeout);
      if (isClosed) return;
      emit(ProfileFormState.of(profile, status: ProfileFormStatus.saved));
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: ProfileFormStatus.failure));
    }
  }
}
