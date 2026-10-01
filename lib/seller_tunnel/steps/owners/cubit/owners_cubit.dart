import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/owners/models/owner_draft.dart';
import 'package:property_repository/property_repository.dart';

part 'owners_state.dart';

/// V1 · the owners form and its persistence in `property_owners`.
///
/// Built from the saved owners of the dossier; when there are none, owner 1
/// is prefilled with the given `firstName` (profile) and `email` (auth).
/// [submit] saves the rows; the page then reports them to the tunnel.
class OwnersCubit extends Cubit<OwnersState> {
  new({
    required this._propertyRepository,
    required this._propertyId,
    required this._profileId,
    List<PropertyOwner> owners = const [],
    OwnershipType? ownershipType,
    String? firstName,
    String? email,
  }) : super(
         OwnersState(
           ownershipType: ownershipType,
           owner: _initialOwner(owners, firstName: firstName, email: email),
           coOwners: [
             for (final owner in owners)
               if (owner.position > 1) OwnerDraft.fromOwner(owner),
           ],
           saved: owners,
         ),
       );

  final PropertyRepository _propertyRepository;
  final String _propertyId;

  /// Profile of the user, linked to owner 1.
  final String _profileId;

  static OwnerDraft _initialOwner(
    List<PropertyOwner> owners, {
    String? firstName,
    String? email,
  }) {
    for (final owner in owners) {
      if (owner.position == 1) return OwnerDraft.fromOwner(owner);
    }
    return OwnerDraft(firstName: firstName ?? '', email: email ?? '');
  }

  /// Set after a failed submission: a response may have been lost (e.g. a
  /// row inserted without its id coming back), so the next attempt reloads
  /// the rows first.
  bool _reloadBeforeSaving = false;

  /// Applies [change] unless a submission is in progress (the form is
  /// disabled meanwhile, so nothing typed is lost).
  void _edit(OwnersState Function(OwnersState state) change) {
    if (state.isSubmitting) return;
    emit(change(state));
  }

  void ownershipSelected(OwnershipType type) =>
      _edit((s) => s.copyWith(ownershipType: type));

  void firstNameChanged(String value) =>
      _edit((s) => s.copyWith(owner: s.owner.copyWith(firstName: value)));

  void lastNameChanged(String value) =>
      _edit((s) => s.copyWith(owner: s.owner.copyWith(lastName: value)));

  void phoneChanged(String value) =>
      _edit((s) => s.copyWith(owner: s.owner.copyWith(phone: value)));

  void emailChanged(String value) =>
      _edit((s) => s.copyWith(owner: s.owner.copyWith(email: value)));

  /// The user left [field]: its error, if any, is shown from now on.
  void fieldLeft(OwnerField field) {
    if (state.touched.contains(field)) return;
    _edit((s) => s.copyWith(touched: {...s.touched, field}));
  }

  void coOwnerAdded(OwnerDraft coOwner) =>
      _edit((s) => s.copyWith(coOwners: [...s.coOwners, coOwner]));

  /// Replaces the co-owner at [index] (keeping its saved row).
  void coOwnerEdited(int index, OwnerDraft coOwner) => _edit((s) {
    final coOwners = [...s.coOwners];
    coOwners[index] = coOwner.copyWith(id: coOwners[index].id);
    return s.copyWith(coOwners: coOwners);
  });

  void coOwnerRemoved(int index) =>
      _edit((s) => s.copyWith(coOwners: [...s.coOwners]..removeAt(index)));

  /// "Continuer": shows every error when an answer is missing or invalid;
  /// otherwise saves the owners: owner 1 at position 1, then the co-owners
  /// (none with a single owner) at 2, 3…
  ///
  /// Rows that are no longer wanted are deleted first; kept rows are
  /// updated in place (co-owners only move to lower positions, which the
  /// deletions and earlier moves have freed, so the unique
  /// `(property_id, position)` is never hit); new ones are inserted last.
  /// Unchanged rows are not written. On failure, the progress is kept and
  /// the next attempt starts by reloading the rows.
  Future<void> submit() async {
    if (state.isSubmitting) return;
    if (!state.isValid) {
      emit(
        state.copyWith(
          showErrors: true,
          submitAttempts: state.submitAttempts + 1,
        ),
      );
      return;
    }
    final ownershipType = state.ownershipType;
    final multiple = state.isMultiple;
    emit(
      state.copyWith(
        submitStatus: OwnersSubmitStatus.inProgress,
        submittedOwnershipType: ownershipType,
      ),
    );
    var saved = [...state.saved];
    var owner = state.owner;
    final coOwners = [...state.coOwners];
    try {
      if (_reloadBeforeSaving) {
        saved = await _propertyRepository.getOwners(_propertyId);
        owner = _adopt(owner, 1, saved, {
          for (final coOwner in coOwners) ?coOwner.id,
        });
        for (var i = 0; i < coOwners.length; i++) {
          coOwners[i] = _adopt(coOwners[i], i + 2, saved, {
            ?owner.id,
            for (final coOwner in coOwners) ?coOwner.id,
          });
        }
        _reloadBeforeSaving = false;
      }
      final wanted = {
        owner.id,
        if (multiple)
          for (final coOwner in coOwners) coOwner.id,
      };
      for (final row in [...saved]) {
        if (wanted.contains(row.id)) continue;
        await _propertyRepository.deleteOwner(row.id!);
        saved.remove(row);
      }
      Future<OwnerDraft> write(OwnerDraft draft, int position) async {
        final row = draft.toOwner(
          propertyId: _propertyId,
          position: position,
          profileId: position == 1 ? _profileId : null,
        );
        final index = saved.indexWhere((s) => s.id != null && s.id == row.id);
        if (index >= 0 && saved[index] == row) return draft;
        final result = await _propertyRepository.saveOwner(row);
        if (index >= 0) {
          saved[index] = result;
        } else {
          saved.add(result);
        }
        return draft.copyWith(id: result.id);
      }

      owner = await write(owner, 1);
      if (multiple) {
        for (var i = 0; i < coOwners.length; i++) {
          coOwners[i] = await write(coOwners[i], i + 2);
        }
      }
      saved.sort((a, b) => a.position.compareTo(b.position));
      if (isClosed) return;
      emit(
        _withIds(
          owner,
          multiple ? coOwners : const [],
        ).copyWith(saved: saved, submitStatus: OwnersSubmitStatus.success),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      _reloadBeforeSaving = true;
      addError(error, stackTrace);
      emit(
        _withIds(
          owner,
          coOwners,
        ).copyWith(saved: saved, submitStatus: OwnersSubmitStatus.failure),
      );
    }
  }

  /// The current state with the ids given to [owner] and [coOwners] while
  /// saving (the drafts themselves could not change meanwhile).
  OwnersState _withIds(OwnerDraft owner, List<OwnerDraft> coOwners) {
    return state.copyWith(
      owner: state.owner.copyWith(id: owner.id),
      coOwners: [
        for (final (i, coOwner) in coOwners.indexed)
          state.coOwners[i].copyWith(id: coOwner.id),
      ],
    );
  }

  /// [draft] with the id of the reloaded row at [position] when it has
  /// none yet (its insert succeeded but the answer was lost) and that row
  /// is not [claimed] by another draft.
  static OwnerDraft _adopt(
    OwnerDraft draft,
    int position,
    List<PropertyOwner> rows,
    Set<String> claimed,
  ) {
    if (draft.id != null) return draft;
    for (final row in rows) {
      if (row.position == position && !claimed.contains(row.id)) {
        return draft.copyWith(id: row.id);
      }
    }
    return draft;
  }
}
