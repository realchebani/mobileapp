import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/models/property_type_profile.dart';
import 'package:mobileapp/seller_tunnel/models/seller_tunnel_step.dart';
import 'package:property_repository/property_repository.dart';

part 'seller_tunnel_state.dart';

/// One seller dossier (a property) and its child
/// collections, shared by every screen of that property: its home, the
/// tunnel steps, V8b, V9b (provided by `PropertyRouteScope`, one cubit per
/// property kept by `SellerTunnelCubits` for the whole seller space).
///
/// [load] fetches the property and its child collections. Step screens save
/// their answers with [saveAndContinue] (or [save]); they manage child rows
/// with the `PropertyRepository` (from the context) and report the changes
/// with [updateChildren].
class SellerTunnelCubit extends Cubit<SellerTunnelState> {
  new({
    required this._propertyRepository,
    required this._propertyId,
    this._timeout = defaultTimeout,
  }) : super(const SellerTunnelState());

  /// Delay after which loading or saving is considered failed.
  static const defaultTimeout = Duration(seconds: 15);

  final PropertyRepository _propertyRepository;
  final Duration _timeout;

  final String _propertyId;

  /// Loads the property and its child collections.
  Future<void> load() async {
    if (state.status == SellerTunnelStatus.loading) return;
    emit(const SellerTunnelState(status: SellerTunnelStatus.loading));
    try {
      final repository = _propertyRepository;
      final id = _propertyId;
      final property = await repository.getProperty(id).timeout(_timeout);
      final (owners, parcels, estimates, rooms, items, documents) = await (
        repository.getOwners(id),
        repository.getParcels(id),
        repository.getPreviousEstimates(id),
        repository.getRooms(id),
        repository.getLifestyleItems(id),
        repository.getDocuments(id),
      ).wait.timeout(_timeout);
      if (isClosed) return;
      emit(
        SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: property,
          owners: owners,
          parcels: parcels,
          previousEstimates: estimates,
          rooms: rooms,
          lifestyleItems: items,
          documents: documents,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        SellerTunnelState(
          status: SellerTunnelStatus.failure,
          notFound: error is PropertyNotFoundFailure,
        ),
      );
    }
  }

  /// Loads the dossier again, after a failure.
  Future<void> retry() => load();

  /// Reloads the dossier in the background (pull to refresh on the seller
  /// space): unlike [load], the current state stays shown while it loads
  /// and is kept on failure, which is rethrown (the caller tells the user).
  Future<void> refresh() async {
    final current = state.property;
    if (current == null || state.status != SellerTunnelStatus.success) return;
    try {
      final repository = _propertyRepository;
      final id = current.id;
      final (property, owners, rooms, items, documents) = await (
        repository.getProperty(id),
        repository.getOwners(id),
        repository.getRooms(id),
        repository.getLifestyleItems(id),
        repository.getDocuments(id),
      ).wait.timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          property: property,
          owners: owners,
          rooms: rooms,
          lifestyleItems: items,
          documents: documents,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      rethrow;
    }
  }

  /// Saves the columns of [patch] (keys from `PropertyColumns`).
  ///
  /// `saveStatus` goes through [SellerTunnelSaveStatus.inProgress] to
  /// [SellerTunnelSaveStatus.success] (with the updated property) or
  /// [SellerTunnelSaveStatus.failure].
  Future<void> save(Map<String, Object?> patch) => _save(patch);

  /// Saves [patch] for [step] and moves the resume point past it. On
  /// success, `nextStep` is the screen to open (`PropertyRouteScope`
  /// navigates to it): the next screen of the type of the property (the
  /// type given by [patch] when it changes it, on V3).
  Future<void> saveAndContinue(
    SellerTunnelStep step, [
    Map<String, Object?> patch = const {},
  ]) {
    final next = _profileAfter(patch).nextAfter(step);
    final currentStep = state.property?.currentStep ?? 1;
    return _save({
      ...patch,
      PropertyColumns.currentStep: next.number > currentStep
          ? next.number
          : currentStep,
    }, from: step);
  }

  /// The profile of the property once [patch] is saved.
  PropertyTypeProfile _profileAfter(Map<String, Object?> patch) {
    if (!patch.containsKey(PropertyColumns.propertyType)) return state.profile;
    return PropertyTypeProfile.of(
      patch[PropertyColumns.propertyType] as PropertyType?,
    );
  }

  Future<void> _save(
    Map<String, Object?> patch, {
    SellerTunnelStep? from,
  }) async {
    final property = state.property;
    if (property == null || state.isSaving) return;
    emit(state.copyWith(saveStatus: SellerTunnelSaveStatus.inProgress));
    try {
      final updated = await _propertyRepository
          .updateProperty(property.id, patch)
          .timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          property: updated,
          saveStatus: SellerTunnelSaveStatus.success,
          nextStep: from == null
              ? null
              : PropertyTypeProfile.of(updated.propertyType).nextAfter(from),
          continuedFrom: from,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(saveStatus: SellerTunnelSaveStatus.failure));
    }
  }

  /// Replaces the given child collections after a step saved them.
  void updateChildren({
    List<PropertyOwner>? owners,
    List<PropertyParcel>? parcels,
    List<PreviousEstimate>? previousEstimates,
    List<Room>? rooms,
    List<LifestyleItem>? lifestyleItems,
    List<PropertyDocument>? documents,
  }) {
    emit(
      state.copyWith(
        owners: owners,
        parcels: parcels,
        previousEstimates: previousEstimates,
        rooms: rooms,
        lifestyleItems: lifestyleItems,
        documents: documents,
      ),
    );
  }
}
