import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  const propertyId = 'property-id';
  const row = {
    'id': 'v1',
    'property_id': propertyId,
    'value_eur': 525000,
    'low_eur': 505000,
    'high_eur': 545000,
    'expert_display_name': 'Julien M.',
    'certified_at': '2026-09-25T10:00:00Z',
    'valid_until': '2026-12-25',
  };

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late ValuationRepository repository;

  http.Response json(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
    request: current,
  );

  http.Response error() =>
      json({'message': 'permission denied', 'code': '42501'}, status: 401);

  setUp(() {
    requests = [];
    client = SupabaseClient(
      'https://project.supabase.co',
      'publishable-key',
      httpClient: MockClient((request) async {
        requests.add(current = request);
        return respond(request);
      }),
    );
    repository = ValuationRepository(client: client);
  });

  tearDown(() => client.dispose());

  group('getLatestValuation', () {
    test('returns the latest valuation of the property', () async {
      respond = (_) => json([row]);
      final valuation = await repository.getLatestValuation(propertyId);
      expect(valuation?.id, 'v1');
      final request = requests.single;
      expect(request.url.path, '/rest/v1/valuations');
      expect(request.url.queryParameters, {
        'select': '*',
        'property_id': 'eq.$propertyId',
        'order': 'certified_at.desc.nullslast',
        'limit': '1',
      });
    });

    test('returns null when there is none', () async {
      respond = (_) => json(<Object>[]);
      expect(await repository.getLatestValuation(propertyId), isNull);
    });

    test('throws ValuationLoadFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.getLatestValuation(propertyId),
        throwsA(
          isA<ValuationLoadFailure>()
              .having((e) => e.error, 'error', isNotNull)
              .having((e) => e.toString(), 'toString', startsWith('Valu')),
        ),
      );
    });
  });

  group('getReportUrl', () {
    const path = 'u/p/report.pdf';

    test('signs a URL in the reports bucket', () async {
      respond = (_) => json({'signedURL': '/object/sign/x?token=t'});
      expect(
        await repository.getReportUrl(path),
        startsWith('https://project.supabase.co/storage/v1/object/sign/x'),
      );
      final request = requests.single;
      expect(
        request.url.path,
        '/storage/v1/object/sign/valuation-reports/$path',
      );
      expect(jsonDecode(request.body), containsPair('expiresIn', 600));
    });

    test('throws ValuationLoadFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.getReportUrl(path),
        throwsA(isA<ValuationLoadFailure>()),
      );
    });
  });
}
