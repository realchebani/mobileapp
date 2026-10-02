import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:property_repository/property_repository.dart';

part 'new_property_state.dart';

/// "Ajouter un bien" (EPIC-13): type, lot ("Vendu avec un autre bien ?")
/// and the information copied from an existing property (owners, identity
/// document, owner decisions Q1–Q2).
///
/// [submit] is retry-safe: the ids of the new property and lot are chosen
/// once, and each step done is not done again (a failed copy is retried
/// alone).
class NewPropertyCubit extends Cubit<NewPropertyState> {
  new({
    required this._propertyRepository,
    required this._ownerId,
    required List<Property> properties,
    String Function()? newId,
    this._timeout = const Duration(seconds: 15),
  }) : _propertyId = (newId ?? generateUuidV4)(),
       _lotId = (newId ?? generateUuidV4)(),
       super(NewPropertyState(properties: properties));

  final PropertyRepository _propertyRepository;
  final String _ownerId;
  final Duration _timeout;
  final String _propertyId;
  final String _lotId;

  bool _ownersCopied = false;
  final _copiedDocuments = <String>{};

  void typeSelected(PropertyType type) => emit(state.copyWith(type: type));

  /// Sold with [partnerId] (null: on its own).
  void partnerSelected(String? partnerId) =>
      emit(state.copyWith(partnerId: () => partnerId));

  void sourceSelected(String sourceId) =>
      emit(state.copyWith(sourceId: sourceId));

  void reuseOwnersChanged({required bool reuse}) =>
      emit(state.copyWith(reuseOwners: reuse));

  void reuseIdentityChanged({required bool reuse}) =>
      emit(state.copyWith(reuseIdentity: reuse));

  /// Creates the property (and its lot), then copies the information.
  Future<void> submit() async {
    if (state.isBusy) return;
    final type = state.type;
    if (type == null) {
      emit(
        state.copyWith(
          showErrors: true,
          submitAttempts: state.submitAttempts + 1,
        ),
      );
      return;
    }
    emit(state.copyWith(status: NewPropertyStatus.inProgress));
    var property = state.property;
    var lot = state.lot;
    try {
      if (property == null) {
        final partner = state.partner;
        if (partner != null) lot = await _lotWith(partner);
        property = await _propertyRepository
            .createProperty(
              id: _propertyId,
              ownerId: _ownerId,
              type: type,
              lotId: lot?.id,
            )
            .timeout(_timeout);
      }
    } on PropertyLimitFailure catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(state.copyWith(status: NewPropertyStatus.limitReached, lot: lot));
      return;
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(state.copyWith(status: NewPropertyStatus.failure, lot: lot));
      return;
    }
    try {
      await _copy(property);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(
        state.copyWith(
          status: NewPropertyStatus.copyFailure,
          property: property,
          lot: lot,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: NewPropertyStatus.success,
        property: property,
        lot: lot,
      ),
    );
  }

  /// The lot of [partner], created with it when it has none.
  Future<PropertyLot> _lotWith(Property partner) async {
    final existing = partner.lotId;
    if (existing != null) {
      final lots = await _propertyRepository
          .listLots(_ownerId)
          .timeout(_timeout);
      final lot = lots.where((lot) => lot.id == existing).firstOrNull;
      if (lot != null) return lot;
    }
    var lot = await _propertyRepository
        .createLot(id: _lotId, ownerId: _ownerId)
        .timeout(_timeout);
    await _propertyRepository
        .setPropertyLot(partner.id, lot.id)
        .timeout(_timeout);
    if (lot.mainPropertyId == null) {
      lot = await _propertyRepository
          .updateLot(lot.id, {PropertyLotColumns.mainPropertyId: partner.id})
          .timeout(_timeout);
    }
    return lot;
  }

  /// Copies the owners and the identity document of the source property.
  Future<void> _copy(Property property) async {
    final source = state.source;
    if (source == null) return;
    if (state.reuseOwners && !_ownersCopied) {
      final owners = await _propertyRepository
          .copyOwners(fromPropertyId: source.id, toPropertyId: property.id)
          .timeout(_timeout);
      if (owners.isNotEmpty) {
        await _propertyRepository
            .updateProperty(property.id, {
              PropertyColumns.ownershipType: source.ownershipType,
              PropertyColumns.provenance: {
                ...property.provenance,
                Property.ownersCopiedFromKey: source.id,
              },
            })
            .timeout(_timeout);
      }
      _ownersCopied = true;
    }
    if (state.reuseIdentity) {
      final documents = await _propertyRepository
          .getDocuments(source.id)
          .timeout(_timeout);
      for (final document in documents) {
        if (document.kind != DocumentKind.identityDocument ||
            document.status == DocumentStatus.rejected ||
            _copiedDocuments.contains(document.id)) {
          continue;
        }
        await _propertyRepository
            .copyDocument(
              document,
              ownerId: _ownerId,
              toPropertyId: property.id,
            )
            .timeout(_timeout);
        _copiedDocuments.add(document.id);
      }
    }
  }
}
