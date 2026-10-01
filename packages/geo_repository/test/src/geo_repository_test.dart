import 'dart:async';
import 'dart:convert';

import 'package:geo_repository/geo_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  const point = GeoPoint(45.707956, 4.739579);

  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) respond;
  late GeoRepository repository;

  http.Response json(String body, {int status = 200}) => http.Response.bytes(
    utf8.encode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  setUp(() {
    requests = [];
    repository = GeoRepository(
      httpClient: MockClient((request) {
        requests.add(request);
        return respond(request);
      }),
      timeout: const Duration(milliseconds: 50),
    );
  });

  tearDown(() => repository.close());

  test('can be created with the default HTTP client', () {
    GeoRepository().close();
  });

  group('searchAddresses', () {
    test('returns the matching BAN addresses', () async {
      respond = (_) async => json(searchResponse);

      final addresses = await repository.searchAddresses(
        ' 12 rue de la colombe chaponost ',
      );

      expect(addresses, [
        const GeoAddress(
          id: '69043_jj2dze_00012',
          label: '12 rue de la Colombe 69630 Chaponost',
          point: point,
          type: GeoAddressType.housenumber,
          name: '12 rue de la Colombe',
          housenumber: '12',
          street: 'rue de la Colombe',
          postcode: '69630',
          city: 'Chaponost',
          citycode: '69043',
          banId: 'dd5698a6-31fa-4e8e-ab04-28ff4a1604fe',
        ),
      ]);
      final uri = requests.single.url;
      expect(uri.host, 'data.geopf.fr');
      expect(uri.path, '/geocodage/search/');
      expect(uri.queryParameters, {
        'q': '12 rue de la colombe chaponost',
        'limit': '5',
        'autocomplete': '1',
      });
    });

    test('passes the limit and autocomplete options', () async {
      respond = (_) async => json('{"features": []}');

      expect(
        await repository.searchAddresses(
          'Chaponost',
          limit: 2,
          autocomplete: false,
        ),
        isEmpty,
      );
      expect(requests.single.url.queryParameters, {
        'q': 'Chaponost',
        'limit': '2',
        'autocomplete': '0',
      });
    });

    test('normalizes the query as the API requires', () async {
      respond = (_) async => json('{"features": []}');
      await repository.searchAddresses('« 12 rue »');
      expect(requests.single.url.queryParameters['q'], '12 rue »');
      expect(GeoRepository.normalizeQuery('-, 3 ${'a' * 300}'), hasLength(200));
      expect(GeoRepository.normalizeQuery(' ** '), isEmpty);
    });

    test('returns nothing for a short query without calling the API', () async {
      expect(await repository.searchAddresses(' 12 '), isEmpty);
      expect(requests, isEmpty);
    });
  });

  group('reverseGeocode', () {
    test('returns the closest address', () async {
      respond = (_) async => json(reverseResponse);

      final address = await repository.reverseGeocode(point);

      expect(address.label, '12 rue de la Colombe 69630 Chaponost');
      expect(address.citycode, '69043');
      final uri = requests.single.url;
      expect(uri.path, '/geocodage/reverse/');
      expect(uri.queryParameters, {
        'lon': '4.739579',
        'lat': '45.707956',
        'limit': '1',
      });
    });

    test('throws GeoNotFoundFailure when there is no address', () async {
      respond = (_) async =>
          json('{"type": "FeatureCollection", "features": []}');

      await expectLater(
        repository.reverseGeocode(point),
        throwsA(isA<GeoNotFoundFailure>()),
      );
    });
  });

  group('parcelAt', () {
    test('returns the parcel containing the point', () async {
      respond = (_) async => json(parcelResponse);

      final parcel = await repository.parcelAt(point);

      expect(parcel.idu, '69043000AM0076');
      expect(parcel.section, 'AM');
      expect(parcel.numero, '0076');
      expect(parcel.shortNumero, '76');
      expect(parcel.areaM2, 947);
      expect(parcel.codeInsee, '69043');
      expect(parcel.communeName, 'Chaponost');
      expect(parcel.outlines.single, hasLength(11));
      final uri = requests.single.url;
      expect(uri.host, 'apicarto.ign.fr');
      expect(uri.path, '/api/cadastre/parcelle');
      expect(jsonDecode(uri.queryParameters['geom']!), {
        'type': 'Point',
        'coordinates': [4.739579, 45.707956],
      });
    });

    test('throws GeoNotFoundFailure when there is no parcel', () async {
      respond = (_) async => json('{"features": [], "crs": null}');

      await expectLater(
        repository.parcelAt(point),
        throwsA(isA<GeoNotFoundFailure>()),
      );
    });
  });

  group('failures', () {
    Future<void> expectFailure<T extends GeoFailure>() =>
        expectLater(repository.parcelAt(point), throwsA(isA<T>()));

    test('network errors throw GeoNetworkFailure', () async {
      respond = (request) async =>
          throw http.ClientException('offline', request.url);
      await expectFailure<GeoNetworkFailure>();
    });

    test('timeouts throw GeoNetworkFailure', () async {
      respond = (_) => Completer<http.Response>().future;
      await expectFailure<GeoNetworkFailure>();
    });

    test('server errors and rate limits throw GeoNetworkFailure', () async {
      respond = (_) async => json('{}', status: 503);
      await expectFailure<GeoNetworkFailure>();
      respond = (_) async => json('{}', status: 429);
      await expectFailure<GeoNetworkFailure>();
    });

    test('rejected requests throw GeoUnknownFailure', () async {
      respond = (_) async => json('{"code": 400}', status: 400);
      await expectFailure<GeoUnknownFailure>();
    });

    test('other client errors throw GeoUnknownFailure', () async {
      respond = (_) async => throw StateError('closed');
      await expectFailure<GeoUnknownFailure>();
    });

    test('invalid JSON throws GeoUnknownFailure', () async {
      respond = (_) async => json('<html>');
      await expectFailure<GeoUnknownFailure>();
    });

    test('unexpected responses throw GeoUnknownFailure', () async {
      respond = (_) async => json('[]');
      await expectFailure<GeoUnknownFailure>();
      respond = (_) async => json('{"features": [{"properties": {}}]}');
      await expectFailure<GeoUnknownFailure>();
    });
  });
}
