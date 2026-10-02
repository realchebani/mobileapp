import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';

part 'seller_properties_state.dart';

/// The properties and sale lots of the signed-in seller, for the seller
/// space ("Mes biens", "Ajouter un bien", lots), provided by
/// `SellerTunnelShell` above every `/vendeur` screen.
///
/// [load] lists them and creates the first property of a new seller (as
/// the app always did). Screens that change a property report it with
/// [propertyChanged] (the open dossiers do it on their own, see
/// `SellerTunnelCubits`).
class SellerPropertiesCubit extends Cubit<SellerPropertiesState> {
  new({
    required this._propertyRepository,
    required this._ownerId,
    String Function()? newId,
    this._timeout = const Duration(seconds: 15),
  }) : _newId = newId ?? generateUuidV4,
       super(const SellerPropertiesState());

  final PropertyRepository _propertyRepository;
  final String Function() _newId;
  final Duration _timeout;

  /// The signed-in seller.
  final String _ownerId;

  /// Loads the properties and lots; a seller without property gets a first
  /// draft.
  Future<void> load() async {
    if (state.status == SellerPropertiesStatus.loading) return;
    emit(state.copyWith(status: SellerPropertiesStatus.loading));
    try {
      var (properties, lots, parcels) = await _fetch();
      if (properties.isEmpty) {
        final first = await _propertyRepository
            .createProperty(id: _newId(), ownerId: _ownerId)
            .timeout(_timeout);
        properties = [first];
      }
      if (isClosed) return;
      emit(
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: properties,
          lots: lots,
          parcels: parcels,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      emit(state.copyWith(status: SellerPropertiesStatus.failure));
    }
  }

  Future<(List<Property>, List<PropertyLot>, Map<String, Set<String>>)>
  _fetch() async {
    final (properties, lots) = await (
      _propertyRepository.listProperties(_ownerId),
      _propertyRepository.listLots(_ownerId),
    ).wait.timeout(_timeout);
    final parcels = await _parcelsOf([
      for (final property in properties)
        if (property.lotId != null) property.id,
    ]);
    return (properties, lots, parcels);
  }

  /// The parcels of [propertyIds] (for the lot estimate).
  Future<Map<String, Set<String>>> _parcelsOf(List<String> propertyIds) async {
    final lists = await [
      for (final id in propertyIds) _propertyRepository.getParcels(id),
    ].wait.timeout(_timeout);
    return {
      for (final (index, id) in propertyIds.indexed)
        id: {for (final parcel in lists[index]) parcel.idu},
    };
  }

  /// Reloads in the background (pull to refresh): the current lists stay
  /// shown, and on failure the error is rethrown (the caller tells the
  /// user).
  Future<void> refresh() async {
    try {
      final (properties, lots, parcels) = await _fetch();
      if (isClosed) return;
      emit(
        SellerPropertiesState(
          status: SellerPropertiesStatus.success,
          properties: properties,
          lots: lots,
          parcels: parcels,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      rethrow;
    }
  }

  /// Records a new or changed [property] (and its [lot], if given).
  void propertyChanged(Property property, {PropertyLot? lot}) {
    final properties = [...state.properties];
    final index = properties.indexWhere((p) => p.id == property.id);
    if (index < 0) {
      properties.add(property);
    } else if (properties[index] == property && lot == null) {
      return;
    } else {
      properties[index] = property;
    }
    emit(
      state.copyWith(
        properties: properties,
        lots: lot == null ? null : _withLot(lot),
      ),
    );
  }

  /// Records a new or changed [lot].
  void lotChanged(PropertyLot lot) => emit(state.copyWith(lots: _withLot(lot)));

  List<PropertyLot> _withLot(PropertyLot lot) {
    final lots = [...state.lots];
    final index = lots.indexWhere((l) => l.id == lot.id);
    if (index < 0) {
      lots.add(lot);
    } else {
      lots[index] = lot;
    }
    return lots;
  }

  /// Deletes the draft [property] (its files first) and the lot it leaves
  /// empty, if any. Throws a `PropertyFailure` on error (nothing changes
  /// in the list then).
  Future<void> deleteProperty(Property property) async {
    await _propertyRepository.deleteProperty(property).timeout(_timeout);
    final lotId = property.lotId;
    final properties = [
      for (final p in state.properties)
        if (p.id != property.id) p,
    ];
    var lots = state.lots;
    if (lotId != null && !properties.any((p) => p.lotId == lotId)) {
      try {
        await _propertyRepository.deleteLot(lotId).timeout(_timeout);
        lots = [
          for (final lot in lots)
            if (lot.id != lotId) lot,
        ];
      } on Object catch (error, stackTrace) {
        // The empty lot only shows as empty; it can be dissolved later.
        addError(error, stackTrace);
      }
    }
    if (isClosed) return;
    emit(state.copyWith(properties: properties, lots: lots));
  }

  /// Dissolves the lot [lotId]: its properties leave it. Throws a
  /// `PropertyFailure` on error ([LotFrozenFailure] once an expert took a
  /// member over).
  Future<void> deleteLot(String lotId) async {
    await _propertyRepository.deleteLot(lotId).timeout(_timeout);
    if (isClosed) return;
    emit(
      state.copyWith(
        lots: [
          for (final lot in state.lots)
            if (lot.id != lotId) lot,
        ],
        properties: [
          for (final property in state.properties)
            if (property.lotId == lotId) _withoutLot(property) else property,
        ],
      ),
    );
  }

  /// Groups [members] (at least two open properties, in no lot) into the
  /// new sale lot [lotId] sold with [saleMode], whose main property is the
  /// first one: all or nothing (no partial lot on failure). Retry-safe
  /// ([lotId], chosen by the caller, is reused). Throws a
  /// `PropertyFailure` on error.
  Future<void> createLot({
    required String lotId,
    required List<Property> members,
    LotSaleMode saleMode = LotSaleMode.together,
  }) async {
    final lot = await _propertyRepository
        .createLotWith(
          id: lotId,
          propertyIds: [for (final member in members) member.id],
          saleMode: saleMode,
        )
        .timeout(_timeout);
    await _recordMembership([
      for (final member in members)
        Property.fromJson({...member.toJson(), PropertyColumns.lotId: lot.id}),
    ], lot);
  }

  /// Puts [property] in the lot [lotId] (null: out of its lot). Throws a
  /// `PropertyFailure` on error ([LotFrozenFailure] for a frozen lot).
  Future<void> setLot(Property property, String? lotId) async {
    final updated = await _propertyRepository
        .setPropertyLot(property.id, lotId)
        .timeout(_timeout);
    final previous = state.lotById(property.lotId);
    await _recordMembership([updated], null);
    // The main property left: the database cleared it.
    if (previous != null && previous.mainPropertyId == property.id) {
      lotChanged(
        PropertyLot.fromJson({
          ...previous.toJson(),
          PropertyLotColumns.mainPropertyId: null,
        }),
      );
    }
  }

  /// Updates the lot [lotId] with [patch] (keys from [PropertyLotColumns]).
  /// Throws a `PropertyFailure` on error.
  Future<void> updateLot(String lotId, Map<String, Object?> patch) async {
    final lot = await _propertyRepository
        .updateLot(lotId, patch)
        .timeout(_timeout);
    if (!isClosed) lotChanged(lot);
  }

  Future<void> _recordMembership(
    List<Property> changed,
    PropertyLot? lot,
  ) async {
    Map<String, Set<String>> parcels;
    try {
      parcels = await _parcelsOf([
        for (final property in changed)
          if (property.lotId != null) property.id,
      ]);
    } on Object catch (error, stackTrace) {
      // Only the lot estimate needs them; a refresh loads them again.
      addError(error, stackTrace);
      parcels = const {};
    }
    if (isClosed) return;
    final properties = [
      for (final property in state.properties)
        changed.where((p) => p.id == property.id).firstOrNull ?? property,
    ];
    emit(
      state.copyWith(
        properties: properties,
        lots: lot == null ? null : _withLot(lot),
        parcels: {...state.parcels, ...parcels},
      ),
    );
  }

  static Property _withoutLot(Property property) =>
      Property.fromJson({...property.toJson(), PropertyColumns.lotId: null});
}
