import 'dart:async';
import 'dart:convert';

import 'package:geo_repository/geo_repository.dart';
import 'package:http/http.dart' as http;

/// {@template geo_repository}
/// French public geographic data, without API key:
///
/// - addresses from the Base Adresse Nationale, served by the IGN
///   Géoplateforme geocoding service (`data.geopf.fr/geocodage`, which
///   replaced `api-adresse.data.gouv.fr`): search / autocomplete and
///   reverse geocoding;
/// - cadastral parcels from API Carto (`apicarto.ign.fr`, IGN).
///
/// Every method throws a [GeoFailure] on error.
/// {@endtemplate}
class GeoRepository {
  /// {@macro geo_repository}
  new({http.Client? httpClient, this._timeout = defaultTimeout})
    : _client = httpClient ?? http.Client();

  /// Delay after which a request is considered failed.
  static const defaultTimeout = Duration(seconds: 10);

  /// Base URL of the address API (BAN, Géoplateforme geocoding).
  static final Uri addressApi = Uri.parse('https://data.geopf.fr/geocodage');

  /// Base URL of the cadastre API (API Carto).
  static final Uri cadastreApi = Uri.parse(
    'https://apicarto.ign.fr/api/cadastre',
  );

  /// Minimum length of a search query (shorter ones are rejected by the
  /// API).
  static const minQueryLength = 3;

  /// Maximum length of a search query (longer ones are rejected by the
  /// API).
  static const maxQueryLength = 200;

  static final RegExp _leadingSymbols = RegExp(
    r'^[^\p{L}\p{N}]+',
    unicode: true,
  );

  /// [query] as the API accepts it: starting with a letter or a digit, at
  /// most [maxQueryLength] characters.
  static String normalizeQuery(String query) {
    final q = query.replaceFirst(_leadingSymbols, '').trim();
    return q.length > maxQueryLength
        ? q.substring(0, maxQueryLength).trim()
        : q;
  }

  final http.Client _client;
  final Duration _timeout;

  /// Addresses matching [query] (at most [limit]), best first. With
  /// [autocomplete], [query] may be the beginning of an address.
  ///
  /// [query] is normalized with [normalizeQuery]; returns an empty list
  /// without calling the API when it has fewer than [minQueryLength]
  /// characters.
  Future<List<GeoAddress>> searchAddresses(
    String query, {
    int limit = 5,
    bool autocomplete = true,
  }) async {
    final q = normalizeQuery(query);
    if (q.length < minQueryLength) return const [];
    final json = await _get(
      addressApi.replace(
        path: '${addressApi.path}/search/',
        queryParameters: {
          'q': q,
          'limit': '$limit',
          'autocomplete': autocomplete ? '1' : '0',
        },
      ),
    );
    return _parse(json, (features) => features.map(GeoAddress.fromFeature));
  }

  /// The address closest to [point].
  ///
  /// Throws [GeoNotFoundFailure] when there is none nearby.
  Future<GeoAddress> reverseGeocode(GeoPoint point) async {
    final json = await _get(
      addressApi.replace(
        path: '${addressApi.path}/reverse/',
        queryParameters: {
          'lon': '${point.lng}',
          'lat': '${point.lat}',
          'limit': '1',
        },
      ),
    );
    return _first<GeoAddress>(json, GeoAddress.fromFeature, point);
  }

  /// The cadastral parcel containing [point].
  ///
  /// Throws [GeoNotFoundFailure] when there is none (e.g. a road).
  Future<CadastreParcel> parcelAt(GeoPoint point) async {
    final json = await _get(
      cadastreApi.replace(
        path: '${cadastreApi.path}/parcelle',
        queryParameters: {
          'geom': jsonEncode({
            'type': 'Point',
            'coordinates': point.toGeoJson(),
          }),
        },
      ),
    );
    return _first<CadastreParcel>(json, CadastreParcel.fromFeature, point);
  }

  /// Closes the HTTP client.
  void close() => _client.close();

  Future<Object?> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(_timeout);
    } on TimeoutException catch (error, stackTrace) {
      Error.throwWithStackTrace(GeoNetworkFailure(error), stackTrace);
    } on http.ClientException catch (error, stackTrace) {
      Error.throwWithStackTrace(GeoNetworkFailure(error), stackTrace);
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(GeoUnknownFailure(error), stackTrace);
    }
    final status = response.statusCode;
    if (status >= 500 || status == 429) {
      throw GeoNetworkFailure('HTTP $status');
    }
    if (status != 200) throw GeoUnknownFailure('HTTP $status');
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(GeoUnknownFailure(error), stackTrace);
    }
  }

  T _first<T>(
    Object? json,
    T Function(Map<String, dynamic> feature) fromFeature,
    GeoPoint point,
  ) {
    final items = _parse(json, (features) => features.take(1).map(fromFeature));
    if (items.isEmpty) throw GeoNotFoundFailure(point);
    return items.single;
  }

  static List<T> _parse<T>(
    Object? json,
    Iterable<T> Function(Iterable<Map<String, dynamic>> features) map,
  ) {
    try {
      final features = (json! as Map<String, dynamic>)['features'] as List;
      return map(features.cast<Map<String, dynamic>>()).toList();
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(GeoUnknownFailure(error), stackTrace);
    }
  }
}
