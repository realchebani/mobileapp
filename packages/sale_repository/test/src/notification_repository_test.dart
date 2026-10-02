import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sale_repository/sale_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  const userId = 'user-id';
  final now = DateTime.utc(2026, 10, 1, 12);

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late NotificationRepository repository;

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
    repository = NotificationRepository(client: client, now: () => now);
  });

  tearDown(() => client.dispose());

  test('uses the clock by default', () {
    expect(NotificationRepository(client: client), isNotNull);
  });

  group('getNotifications', () {
    test('returns the notifications, newest first', () async {
      respond = (_) => json([
        {
          'id': 'n1',
          'kind': 'valuation_certified',
          'title': 'Disponible',
          'created_at': '2026-09-25T10:00:00Z',
        },
      ]);
      final notifications = await repository.getNotifications(userId);
      expect(notifications.single.id, 'n1');
      expect(requests.single.url.queryParameters, {
        'select': 'id,kind,title,body,property_id,route,read_at,created_at',
        'user_id': 'eq.$userId',
        'order': 'created_at.desc.nullslast',
        'limit': '50',
      });
    });

    test('throws NotificationFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.getNotifications(userId),
        throwsA(
          isA<NotificationFailure>()
              .having((e) => e.error, 'error', isNotNull)
              .having((e) => e.toString(), 'toString', startsWith('Notif')),
        ),
      );
    });
  });

  group('markRead', () {
    test('sets read_at on the unread notifications', () async {
      respond = (_) => json(<Object>[]);
      expect(await repository.markRead(['n1', 'n2']), now);
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.queryParameters, {
        'id': 'in.("n1","n2")',
        'read_at': 'is.null',
      });
      expect(jsonDecode(request.body), {'read_at': now.toIso8601String()});
    });

    test('does nothing without ids', () async {
      expect(await repository.markRead(const []), now);
      expect(requests, isEmpty);
    });

    test('throws NotificationFailure on error', () async {
      respond = (_) => error();
      await expectLater(
        repository.markRead(['n1']),
        throwsA(isA<NotificationFailure>()),
      );
    });
  });
}
