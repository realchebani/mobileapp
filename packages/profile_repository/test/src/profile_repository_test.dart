import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:profile_repository/profile_repository.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

void main() {
  const userId = 'user-id';

  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late http.Request current;
  late SupabaseClient client;
  late ProfileRepository repository;

  http.Response json(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
    request: current,
  );

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
    repository = ProfileRepository(client: client);
  });

  tearDown(() => client.dispose());

  group('ProfileRepository', () {
    group('getProfile', () {
      test('returns the profile of the user', () async {
        respond = (_) => json([
          {'id': userId, 'first_name': 'Jane', 'role': 'seller'},
        ]);

        expect(
          await repository.getProfile(userId),
          const Profile(id: userId, firstName: 'Jane', role: UserRole.seller),
        );
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.url.path, '/rest/v1/profiles');
        expect(request.url.queryParameters, {
          'select': 'id,first_name,role',
          'id': 'eq.$userId',
        });
      });

      test('throws ProfileNotFoundFailure when there is no row', () async {
        respond = (_) => json(<Object>[]);
        await expectLater(
          repository.getProfile(userId),
          throwsA(
            isA<ProfileNotFoundFailure>().having(
              (e) => e.userId,
              'userId',
              userId,
            ),
          ),
        );
      });

      test('throws GetProfileFailure on error', () async {
        respond = (_) => json({
          'message': 'permission denied',
          'code': '42501',
        }, status: 401);
        await expectLater(
          repository.getProfile(userId),
          throwsA(
            isA<GetProfileFailure>().having(
              (e) => e.error,
              'error',
              isA<PostgrestException>(),
            ),
          ),
        );
      });
    });

    group('updateRole', () {
      test('updates the role of the user', () async {
        respond = (_) => json([
          {'id': userId},
        ]);

        await repository.updateRole(userId, UserRole.buyer);

        final request = requests.single;
        expect(request.method, 'PATCH');
        expect(request.url.path, '/rest/v1/profiles');
        expect(request.url.queryParameters, {
          'id': 'eq.$userId',
          'select': 'id',
        });
        expect(jsonDecode(request.body), {'role': 'buyer'});
      });

      test('throws ProfileNotFoundFailure when no row was updated', () async {
        respond = (_) => json(<Object>[]);
        await expectLater(
          repository.updateRole(userId, UserRole.seller),
          throwsA(isA<ProfileNotFoundFailure>()),
        );
      });

      test('throws UpdateRoleFailure on error', () async {
        respond = (_) => json({
          'message': 'new row violates check constraint',
          'code': '23514',
        }, status: 400);
        await expectLater(
          repository.updateRole(userId, UserRole.seller),
          throwsA(
            isA<UpdateRoleFailure>().having(
              (e) => e.error,
              'error',
              isA<PostgrestException>(),
            ),
          ),
        );
      });
    });
  });

  group('failures', () {
    test('have a readable toString', () {
      expect(
        const ProfileNotFoundFailure('a').toString(),
        'ProfileNotFoundFailure(a)',
      );
      expect(const GetProfileFailure().toString(), 'GetProfileFailure(null)');
      expect(const UpdateRoleFailure().toString(), 'UpdateRoleFailure(null)');
    });
  });
}
