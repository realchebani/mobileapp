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
    try {
      property ??= await _propertyRepository
          .createProperty(id: _propertyId, ownerId: _ownerId, type: type)
          .timeout(_timeout);
    } on PropertyLimitFailure catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(state.copyWith(status: NewPropertyStatus.limitReached));
      return;
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(state.copyWith(status: NewPropertyStatus.failure));
      return;
    }
    // Known from now on, even if a next step fails.
    emit(state.copyWith(property: property));
    try {
      await _joinLot(property);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(state.copyWith(status: NewPropertyStatus.lotFailure));
      return;
    }
    try {
      await _copy(property);
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      emit(state.copyWith(status: NewPropertyStatus.copyFailure));
      return;
    }
    emit(state.copyWith(status: NewPropertyStatus.success));
  }

  bool _lotJoined = false;

  /// Sold with a partner: joins its lot, or creates a lot with both (all
  /// or nothing).
  Future<void> _joinLot(Property property) async {
    final partner = state.partner;
    if (partner == null || _lotJoined) return;
    final existing = partner.lotId;
    if (existing != null) {
      await _propertyRepository
          .setPropertyLot(property.id, existing)
          .timeout(_timeout);
    } else {
      final lot = await _propertyRepository
          .createLotWith(id: _lotId, propertyIds: [partner.id, property.id])
          .timeout(_timeout);
      emit(state.copyWith(lot: lot));
    }
    _lotJoined = true;
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
                ...property.mergeProvenance({
                  PropertyColumns.ownershipType: Provenance.declared,
                }),
                Property.ownersCopiedFromKey: source.id,
              },
            })
            .timeout(_timeout);
      }
      _ownersCopied = true;
    }
    if (state.reuseIdentity) {
      final (documents, copied) = await (
        _propertyRepository.getDocuments(source.id),
        // A copy whose answer was lost is already there: never twice.
        _propertyRepository.getDocuments(property.id),
      ).wait.timeout(_timeout);
      bool alreadyCopied(PropertyDocument document) => copied.any(
        (copy) =>
            copy.kind == document.kind &&
            copy.fileName == document.fileName &&
            copy.sizeBytes == document.sizeBytes,
      );
      for (final document in documents) {
        if (document.kind != DocumentKind.identityDocument ||
            document.status == DocumentStatus.rejected ||
            _copiedDocuments.contains(document.id) ||
            alreadyCopied(document)) {
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
