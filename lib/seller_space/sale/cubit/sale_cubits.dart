import 'dart:async';

import 'package:mobileapp/seller_space/sale/cubit/sale_cubit.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// The seller's properties and lots, read when a sale is loaded.
typedef SaleContextSource = (List<Property>, List<PropertyLot>) Function();

/// The [SaleCubit] of each sale opened, created (and loaded) on first use
/// and kept for the session, so that every screen of a sale shares it. Each
/// change of a sale's formula or stage is told to `onSaleChanged` (to
/// refresh the seller's list of sales).
class SaleCubits {
  new({
    required this._saleRepository,
    required this._propertyRepository,
    required this._valuationRepository,
    required this._ownerId,
    required this._context,
    this._onSaleChanged,
    this._userAgent,
  });

  final SaleRepository _saleRepository;
  final PropertyRepository _propertyRepository;
  final ValuationRepository _valuationRepository;
  final String _ownerId;
  final SaleContextSource _context;
  final void Function()? _onSaleChanged;
  final String? _userAgent;
  final _cubits = <String, SaleCubit>{};
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// The cubit of the sale [saleId].
  SaleCubit of(String saleId) {
    final existing = _cubits[saleId];
    if (existing != null) return existing;
    final cubit = _cubits[saleId] = SaleCubit(
      saleRepository: _saleRepository,
      propertyRepository: _propertyRepository,
      valuationRepository: _valuationRepository,
      saleId: saleId,
      ownerId: _ownerId,
      userAgent: _userAgent,
    );
    final onChanged = _onSaleChanged;
    if (onChanged != null) {
      _subscriptions.add(
        cubit.stream
            .map((state) => (state.sale?.formula, state.sale?.stage))
            .distinct()
            .skip(1)
            .listen((_) => onChanged()),
      );
    }
    final (properties, lots) = _context();
    unawaited(cubit.load(properties: properties, lots: lots));
    return cubit;
  }

  /// Closes every cubit.
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final cubit in _cubits.values) {
      await cubit.close();
    }
    _cubits.clear();
  }
}
