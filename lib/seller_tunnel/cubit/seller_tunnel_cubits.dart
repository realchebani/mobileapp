import 'dart:async';

import 'package:mobileapp/seller_tunnel/cubit/seller_tunnel_cubit.dart';
import 'package:property_repository/property_repository.dart';

/// The [SellerTunnelCubit] of each property opened in the seller space,
/// created on first use and kept until the seller space closes, so that
/// every screen of one property (its home, the tunnel, V8b, V9b) shares the
/// same dossier, and screens of two properties never mix them.
///
/// The `onPropertyChanged` callback is told every change of a loaded
/// property (to keep the list of "Mes biens" current).
class SellerTunnelCubits {
  new({
    required this._propertyRepository,
    this._onPropertyChanged,
    this._timeout = SellerTunnelCubit.defaultTimeout,
  });

  final PropertyRepository _propertyRepository;
  final void Function(Property property)? _onPropertyChanged;
  final Duration _timeout;
  final _cubits = <String, SellerTunnelCubit>{};
  final _subscriptions = <String, StreamSubscription<Property?>>{};

  /// The cubit of the property [propertyId], created (and loaded) on first
  /// use.
  SellerTunnelCubit of(String propertyId) {
    final existing = _cubits[propertyId];
    if (existing != null) return existing;
    final cubit = SellerTunnelCubit(
      propertyRepository: _propertyRepository,
      propertyId: propertyId,
      timeout: _timeout,
    );
    _cubits[propertyId] = cubit;
    final onChanged = _onPropertyChanged;
    if (onChanged != null) {
      _subscriptions[propertyId] = cubit.stream
          .map((state) => state.property)
          .distinct()
          .listen((property) {
            if (property != null) onChanged(property);
          });
    }
    unawaited(cubit.load());
    return cubit;
  }

  /// Forgets the property [propertyId] (deleted): its cubit is closed.
  Future<void> forget(String propertyId) async {
    await _subscriptions.remove(propertyId)?.cancel();
    await _cubits.remove(propertyId)?.close();
  }

  /// Closes every cubit.
  Future<void> close() async {
    for (final id in [..._cubits.keys]) {
      await forget(id);
    }
  }
}
