/// {@template geo_failure}
/// Base class of the failures thrown by `GeoRepository`.
/// {@endtemplate}
sealed class GeoFailure implements Exception {
  /// {@macro geo_failure}
  const new([this.error]);

  /// The underlying error, if any.
  final Object? error;

  String get _name;

  @override
  String toString() => '$_name($error)';
}

/// The service could not be reached or is temporarily unavailable
/// (offline, timeout, server error, rate limit): retrying later may work.
final class GeoNetworkFailure extends GeoFailure {
  const new([super.error]);

  @override
  String get _name => 'GeoNetworkFailure';
}

/// Nothing was found (no address near a point, no parcel at a point).
final class GeoNotFoundFailure extends GeoFailure {
  const new([super.error]);

  @override
  String get _name => 'GeoNotFoundFailure';
}

/// Any other error: rejected request or unexpected response.
final class GeoUnknownFailure extends GeoFailure {
  const new([super.error]);

  @override
  String get _name => 'GeoUnknownFailure';
}
