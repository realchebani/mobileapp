import 'dart:async';

import 'package:agent_repository/agent_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geo_repository/geo_repository.dart';
import 'package:mobileapp/seller_tunnel/steps/location/data/device_locator.dart';
import 'package:mobileapp/seller_tunnel/voice/voice_form.dart';
import 'package:property_repository/property_repository.dart';

part 'location_state.dart';

/// How a cadastre lookup changes the selection.
enum _Lookup {
  /// New address or position: the parcel there replaces the selection
  /// (cleared when there is none).
  locate,

  /// Map tap: the parcel there replaces the selection (kept when there is
  /// none).
  select,

  /// Map tap while editing: the parcel there is added or removed.
  toggle,
}

/// V2 · Géoloc & cadastre: address autocomplete (BAN), device position,
/// cadastral parcels (API Carto) and special situations.
///
/// [submit] saves the selected parcels (`property_parcels` rows); the view
/// then reports them to the `SellerTunnelCubit` and saves
/// [LocationState.toPatch] with `saveAndContinue`.
///
/// The V2 voice sheet (EPIC-14) answers the special situations
/// ([applyVoiceTurn]); the address is only dictated into its field.
class LocationCubit extends Cubit<LocationState>
    with VoiceFormMixin<LocationState> {
  new({
    required this._geoRepository,
    required this._propertyRepository,
    required this._deviceLocator,
    required Property property,
    required List<PropertyParcel> parcels,
    this._searchDebounce = defaultSearchDebounce,
    this._writeTimeout = defaultWriteTimeout,
  }) : _propertyId = property.id,
       super(LocationState.fromDossier(property, parcels));

  /// Pause after the last keystroke before searching addresses.
  static const defaultSearchDebounce = Duration(milliseconds: 300);

  /// Delay after which saving a parcel row is considered failed.
  static const defaultWriteTimeout = Duration(seconds: 15);

  final GeoRepository _geoRepository;
  final PropertyRepository _propertyRepository;
  final DeviceLocator _deviceLocator;
  final String _propertyId;
  final Duration _searchDebounce;
  final Duration _writeTimeout;

  Timer? _searchTimer;
  int _searchId = 0;

  /// Identifies the latest locate / select lookup: older answers are
  /// dropped, and so are the toggles asked before it.
  int _lookupId = 0;

  /// Toggle lookups still waiting for an answer (each tap is applied).
  int _pendingToggles = 0;

  /// The address field changed: the address becomes manual (its position
  /// and parcels no longer apply) and matching BAN addresses are searched
  /// (debounced).
  void addressChanged(String text) {
    if (text == state.addressText) return;
    _cancelSearch();
    _lookupId++;
    final searchable =
        GeoRepository.normalizeQuery(text).length >=
        GeoRepository.minQueryLength;
    emit(
      state.copyWith(
        addressText: text,
        address: () => null,
        point: () => null,
        parcels: const [],
        parcelConfirmed: false,
        isEditingParcels: false,
        parcelStatus: state.parcelStatus == ParcelLookupStatus.failure
            ? ParcelLookupStatus.failure
            : ParcelLookupStatus.idle,
        suggestions: searchable ? null : const [],
        suggestionsUnavailable: false,
      ),
    );
    if (!searchable) return;
    final id = _searchId;
    _searchTimer = Timer(_searchDebounce, () => _search(text, id));
  }

  Future<void> _search(String text, int id) async {
    List<GeoAddress> results;
    var unavailable = false;
    try {
      results = await _geoRepository.searchAddresses(text);
    } on Object {
      results = const [];
      unavailable = true;
    }
    if (isClosed || id != _searchId) return;
    emit(
      state.copyWith(suggestions: results, suggestionsUnavailable: unavailable),
    );
  }

  void _cancelSearch() {
    _searchTimer?.cancel();
    _searchId++;
  }

  /// A suggestion was picked: locates it and looks up its parcel.
  Future<void> suggestionSelected(GeoAddress address) async {
    _cancelSearch();
    emit(
      state.copyWith(
        addressText: address.label,
        address: () => address,
        point: () => address.point,
        suggestions: const [],
        suggestionsUnavailable: false,
      ),
    );
    await _lookup(address.point, _Lookup.locate);
  }

  /// "Me géolocaliser": device position, its address (reverse geocoding,
  /// optional) and its parcel.
  Future<void> locate() async {
    if (state.isLocating) return;
    emit(state.copyWith(isLocating: true, locateError: () => null));
    final GeoPoint point;
    try {
      point = await _deviceLocator.currentPosition();
    } on DeviceLocationException catch (error) {
      if (isClosed) return;
      emit(state.copyWith(isLocating: false, locateError: () => error.reason));
      return;
    }
    GeoAddress? address;
    try {
      address = await _geoRepository.reverseGeocode(point);
    } on Object {
      // The address can still be typed by hand.
    }
    if (isClosed) return;
    _cancelSearch();
    emit(
      state.copyWith(
        isLocating: false,
        point: () => point,
        address: () => address,
        addressText: address?.label,
        suggestions: const [],
        suggestionsUnavailable: false,
      ),
    );
    await _lookup(point, _Lookup.locate);
  }

  /// The map was tapped at [point]: selects the parcel there or, while
  /// editing, adds or removes it.
  Future<void> mapTapped(GeoPoint point) async {
    final hit = state.parcels.where((parcel) => parcel.contains(point));
    if (state.isEditingParcels) {
      if (hit.isEmpty) return await _lookup(point, _Lookup.toggle);
      final removed = hit.first;
      emit(
        state.copyWith(
          parcels: [
            for (final parcel in state.parcels)
              if (parcel.idu != removed.idu) parcel,
          ],
          parcelStatus: _pendingToggles > 0
              ? ParcelLookupStatus.loading
              : ParcelLookupStatus.success,
        ),
      );
      return;
    }
    if (hit.isNotEmpty) return;
    await _lookup(point, _Lookup.select);
  }

  Future<void> _lookup(GeoPoint point, _Lookup mode) async {
    final toggle = mode == _Lookup.toggle;
    final id = toggle ? _lookupId : ++_lookupId;
    if (toggle) _pendingToggles++;
    emit(state.copyWith(parcelStatus: ParcelLookupStatus.loading));
    CadastreParcel? parcel;
    var status = ParcelLookupStatus.success;
    try {
      parcel = await _geoRepository.parcelAt(point);
    } on GeoNotFoundFailure {
      status = ParcelLookupStatus.notFound;
    } on Object {
      status = ParcelLookupStatus.failure;
    } finally {
      if (toggle) _pendingToggles--;
    }
    if (isClosed || id != _lookupId) return;
    // Other taps still pending: their answers will settle the status.
    final settled = toggle && _pendingToggles > 0
        ? ParcelLookupStatus.loading
        : status;
    if (parcel == null) {
      emit(
        mode == _Lookup.locate
            ? state.copyWith(
                parcelStatus: settled,
                parcels: const [],
                parcelConfirmed: false,
                isEditingParcels: false,
              )
            : state.copyWith(parcelStatus: settled),
      );
      return;
    }
    final found = parcel;
    final parcels = switch (mode) {
      _Lookup.toggle when state.parcels.any((p) => p.idu == found.idu) => [
        for (final p in state.parcels)
          if (p.idu != found.idu) p,
      ],
      _Lookup.toggle => [...state.parcels, found],
      _Lookup.locate || _Lookup.select => [found],
    };
    emit(
      state.copyWith(
        parcelStatus: settled,
        parcels: parcels,
        parcelConfirmed: false,
        isEditingParcels: toggle,
      ),
    );
  }

  /// "Oui, c’est correct".
  void confirmParcels() {
    emit(state.copyWith(parcelConfirmed: true, isEditingParcels: false));
  }

  /// "Modifier / ajouter": map taps now add or remove parcels.
  void editParcels() {
    emit(state.copyWith(parcelConfirmed: false, isEditingParcels: true));
  }

  /// A special situation chip was toggled; "Aucune" excludes the others.
  void situationToggled(SpecialSituation situation, {required bool selected}) {
    final others = state.situations.where((s) => s != situation);
    final situations =
        !selected
              ? others.toList()
              : situation == SpecialSituation.none
              ? [situation]
              : [...others.where((s) => s != SpecialSituation.none), situation]
          ..sort((a, b) => a.index.compareTo(b.index));
    emit(state.copyWith(situations: situations));
  }

  /// The "Autre" free text changed.
  void otherSituationChanged(String text) {
    emit(state.copyWith(otherSituation: text));
  }

  @override
  bool get acceptsVoice => !state.isSubmitting;

  @override
  AgentTurnContext get voiceContext => AgentTurnContext(
    draft: {
      PropertyColumns.specialSituations: [
        for (final situation in state.situations) situation.value,
      ],
      PropertyColumns.specialSituationOther: state.otherSituation.trim().isEmpty
          ? null
          : state.otherSituation.trim(),
    },
  );

  @override
  LocationState applyVoiceTurn(LocationState state, AgentTurn turn) {
    final patch = turn.patch;
    final situations = patch[PropertyColumns.specialSituations];
    final other = patch[PropertyColumns.specialSituationOther];
    return state.copyWith(
      situations: situations is List
          ? (parseDbEnumList(SpecialSituation.values, situations)
              ..sort((a, b) => a.index.compareTo(b.index)))
          : null,
      otherSituation: other is String ? other : null,
      dictated: {...state.dictated, ...patch.keys},
    );
  }

  /// "Continuer": shows the errors if the answers are incomplete, else
  /// saves the parcel rows (deletes the unselected ones, inserts the new
  /// ones).
  Future<void> submit() async {
    if (state.submitStatus == LocationSubmitStatus.inProgress) return;
    if (!state.isValid) {
      emit(
        state.copyWith(
          showErrors: true,
          submitAttempts: state.submitAttempts + 1,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        showErrors: true,
        submitStatus: LocationSubmitStatus.inProgress,
      ),
    );
    final saved = [...state.savedParcels];
    final selected = {for (final parcel in state.parcels) parcel.idu};
    try {
      for (final row in state.savedParcels) {
        if (selected.contains(row.idu)) continue;
        if (row.id case final id?) {
          await _propertyRepository.deleteParcel(id).timeout(_writeTimeout);
        }
        saved.remove(row);
      }
      for (final parcel in state.parcels) {
        if (saved.any((row) => row.idu == parcel.idu)) continue;
        saved.add(
          await _propertyRepository
              .saveParcel(
                PropertyParcel(
                  propertyId: _propertyId,
                  idu: parcel.idu,
                  codeInsee: parcel.codeInsee,
                  section: parcel.section,
                  numero: parcel.numero,
                  areaM2: parcel.areaM2,
                  geometry: parcel.geometry,
                ),
              )
              .timeout(_writeTimeout),
        );
      }
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(
        state.copyWith(
          submitStatus: LocationSubmitStatus.failure,
          savedParcels: saved,
        ),
      );
      return;
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        submitStatus: LocationSubmitStatus.success,
        savedParcels: saved,
      ),
    );
  }

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    return super.close();
  }
}
