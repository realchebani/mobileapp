import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_space/sale/models/sale_entry.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

part 'sale_state.dart';

/// One sale (EPIC-08) and what its screens need: its mandate and service
/// requests, the properties sold with their certified values, the owners
/// of the main property (signer, identity checks) and its documents.
///
/// After each action, [SaleState.failure] is what stopped it (null on
/// success), for the screen to tell; [SaleState.busy] is the running
/// action.
class SaleCubit extends Cubit<SaleState> {
  new({
    required this._saleRepository,
    required this._propertyRepository,
    required this._valuationRepository,
    required this._saleId,
    required this._ownerId,
    String Function()? generateId,
    this._userAgent,
    this._appVersion,
    this._timeout = defaultTimeout,
  }) : _generateId = generateId ?? generateUuidV4,
       super(const SaleState());

  static const defaultTimeout = Duration(seconds: 15);

  final SaleRepository _saleRepository;
  final PropertyRepository _propertyRepository;
  final ValuationRepository _valuationRepository;
  final String _saleId;
  final String _ownerId;
  final String Function() _generateId;
  final Duration _timeout;

  /// Recorded with the signature (device, app version).
  final String? _userAgent;
  final String? _appVersion;

  /// Ids chosen for actions being retried (retry-safe RPCs).
  String? _mandateId;
  final Map<SaleRequestKind, String> _requestIds = {};

  List<Property> _properties = const [];
  List<PropertyLot> _lots = const [];

  /// Loads the sale and its context, given the seller's [properties] and
  /// [lots] (kept for later reloads).
  Future<void> load({
    required List<Property> properties,
    required List<PropertyLot> lots,
  }) async {
    _properties = properties;
    _lots = lots;
    if (state.sale == null) emit(const SaleState());
    await _load();
  }

  /// Reloads everything (pull to refresh, after an action).
  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final sale = await _saleRepository.getSale(_saleId).timeout(_timeout);
      if (isClosed) return;
      if (sale == null) {
        emit(const SaleState(status: SaleLoadStatus.notFound));
        return;
      }
      final members = _membersOf(sale);
      final main = members.firstOrNull;
      final certified = [
        for (final member in members)
          if (member.status == PropertyStatus.certified) member,
      ];
      final (
        mandate,
        requests,
        valuations,
        owners,
        identities,
        documents,
      ) = await (
        _saleRepository.getMandate(sale.id),
        _saleRepository.getRequests(sale.id),
        Future.wait([
          for (final member in certified)
            _valuationRepository.getLatestValuation(member.id),
        ]),
        main == null
            ? Future.value(const <PropertyOwner>[])
            : _propertyRepository.getOwners(main.id),
        main == null
            ? Future.value(const <String, DateTime?>{})
            : _saleRepository.getIdentityVerifications(main.id),
        main == null
            ? Future.value(const <PropertyDocument>[])
            : _propertyRepository.getDocuments(main.id),
      ).wait.timeout(_timeout);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: SaleLoadStatus.ready,
          sale: sale,
          mandate: mandate,
          clearMandate: mandate == null,
          requests: requests,
          members: members,
          valuations: {
            for (final valuation in valuations.nonNulls)
              valuation.propertyId: valuation,
          },
          owners: owners,
          identities: identities,
          documentKinds: {for (final document in documents) document.kind},
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed) return;
      addError(error, stackTrace);
      if (state.sale == null) {
        emit(const SaleState(status: SaleLoadStatus.failure));
      }
    }
  }

  List<Property> _membersOf(Sale sale) {
    if (sale.propertyId != null) {
      return [
        for (final property in _properties)
          if (property.id == sale.propertyId) property,
      ];
    }
    final lot = _lots.where((l) => l.id == sale.lotId).firstOrNull;
    return lot == null ? const [] : SaleEntry.lotMembers(lot, _properties);
  }

  Future<void> _act(
    SaleAction action,
    Future<void> Function() run, {
    bool reload = true,
  }) async {
    if (state.busy != null) return;
    emit(state.copyWith(busy: action, clearFailure: true));
    SaleFailure? failure;
    try {
      await run().timeout(_timeout);
      if (reload) await _load();
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      failure = error is SaleFailure
          ? error
          : SaleFailure(SaleFailureReason.unknown, error: error);
    }
    if (!isClosed) {
      emit(state.copyWith(clearBusy: true, failure: failure));
    }
  }

  /// Changes the formula (while the mandate is not signed).
  Future<void> changeFormula(SaleFormula formula) =>
      _act(SaleAction.formula, () async {
        final sale = state.sale!;
        await _saleRepository.chooseFormula(
          saleId: sale.id,
          formula: formula,
          propertyId: sale.propertyId,
          lotId: sale.lotId,
        );
      });

  /// Signs the TEST mandate with the drawn [signaturePng], then asks for
  /// its PDF in the background.
  Future<void> signMandate({
    required Uint8List signaturePng,
    required bool accepted,
  }) => _act(SaleAction.sign, () async {
    final mandateId = _mandateId ??= _generateId();
    await _saleRepository.signTestMandate(
      ownerId: _ownerId,
      saleId: _saleId,
      mandateId: mandateId,
      signaturePng: signaturePng,
      accepted: accepted,
      userAgent: _userAgent,
      appVersion: _appVersion,
    );
    _mandateId = null;
    unawaited(_renderQuietly(mandateId));
  });

  Future<void> _renderQuietly(String mandateId) async {
    try {
      await _saleRepository.renderMandate(mandateId).timeout(_timeout);
    } on Object catch (error, stackTrace) {
      // Rendered again when the seller opens it.
      if (!isClosed) addError(error, stackTrace);
    }
  }

  /// Prepares a temporary URL of the mandate PDF ([SaleState.mandateUrl]),
  /// rendering the PDF first when needed.
  Future<void> openMandate() async {
    final mandate = state.mandate;
    if (mandate == null) return;
    await _act(SaleAction.mandatePdf, reload: false, () async {
      final path =
          mandate.documentPath ??
          await _saleRepository.renderMandate(mandate.id);
      final url = await _saleRepository.mandateUrl(path);
      if (!isClosed) emit(state.copyWith(mandateUrl: url));
    });
  }

  /// Asks the service [kind] (no payment: a Realesty adviser handles it).
  Future<void> requestService(
    SaleRequestKind kind, {
    List<Diagnostic> diagnostics = const [],
    List<DateTime> preferredSlots = const [],
  }) => _act(SaleAction.request, () async {
    final id = _requestIds[kind] ??= _generateId();
    await _saleRepository.requestService(
      requestId: id,
      saleId: _saleId,
      kind: kind,
      diagnostics: diagnostics,
      preferredSlots: preferredSlots,
    );
    _requestIds.remove(kind);
  });

  /// Cancels the open request [request].
  Future<void> cancelRequest(SaleRequest request) =>
      _act(SaleAction.request, () => _saleRepository.cancelRequest(request.id));

  /// Saves listing columns ([SaleColumns]) and keeps the returned sale.
  Future<void> updateListing(Map<String, Object?> patch) =>
      _act(SaleAction.listing, reload: false, () async {
        final sale = await _saleRepository.updateSale(_saleId, patch);
        if (!isClosed) emit(state.copyWith(sale: sale));
      });

  /// Publishes the listing (a [SaleFailure.missing] list when incomplete).
  Future<void> publish() =>
      _act(SaleAction.publish, () => _saleRepository.publish(_saleId));

  /// Takes the listing offline.
  Future<void> unpublish() =>
      _act(SaleAction.publish, () => _saleRepository.unpublish(_saleId));

  /// Withdraws the sale.
  Future<void> withdraw({String? reason}) => _act(
    SaleAction.withdraw,
    () => _saleRepository.withdraw(_saleId, reason: reason),
  );
}
