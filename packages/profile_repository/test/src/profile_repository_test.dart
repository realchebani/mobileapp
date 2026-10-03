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
          'select':
              'id,first_name,role,last_name,phone,postal_address,locale,'
              'deactivated_at,deletion_due_at',
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

  group('updateDetails', () {
    test('saves the details and returns the profile', () async {
      respond = (_) => json([
        {'id': userId, 'first_name': 'Jane', 'last_name': 'Doe'},
      ]);
      expect(
        await repository.updateDetails(
          userId,
          const ProfileDetails(firstName: ' Jane ', lastName: 'Doe', phone: ''),
        ),
        const Profile(id: userId, firstName: 'Jane', lastName: 'Doe'),
      );
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.queryParameters['id'], 'eq.$userId');
      expect(jsonDecode(request.body), {
        'first_name': 'Jane',
        'last_name': 'Doe',
        'phone': null,
        'postal_address': null,
      });
    });

    test('throws ProfileNotFoundFailure when no row was updated', () async {
      respond = (_) => json(<Object>[]);
      await expectLater(
        repository.updateDetails(userId, const ProfileDetails()),
        throwsA(isA<ProfileNotFoundFailure>()),
      );
    });

    test('throws UpdateProfileFailure on error', () async {
      respond = (_) => json({'message': 'check', 'code': '23514'}, status: 400);
      await expectLater(
        repository.updateLocale(userId, 'en'),
        throwsA(isA<UpdateProfileFailure>()),
      );
    });

    test('updateLocale saves the language', () async {
      respond = (_) => json([
        {'id': userId, 'locale': null},
      ]);
      expect(
        await repository.updateLocale(userId, null),
        const Profile(id: userId),
      );
      expect(jsonDecode(requests.single.body), {'locale': null});
    });
  });

  group('account deletion', () {
    test('getDeletionBlockers reads the blockers', () async {
      respond = (_) => json(['active_sale', 'unknown', 'staff_account']);
      expect(await repository.getDeletionBlockers(), {
        AccountDeletionBlocker.activeSale,
        AccountDeletionBlocker.staffAccount,
      });
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/account_deletion_blockers',
      );
    });

    test('getDeletionBlockers throws AccountDeletionFailure', () async {
      respond = (_) => json({'message': 'boom', 'code': 'XX000'}, status: 500);
      await expectLater(
        repository.getDeletionBlockers(),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (e) => e.blocker,
            'blocker',
            isNull,
          ),
        ),
      );
    });

    test('deactivateAccount returns the deletion date', () async {
      respond = (_) => json('2026-11-02T08:00:00+00:00');
      expect(
        await repository.deactivateAccount(),
        DateTime.utc(2026, 11, 2, 8),
      );
      expect(requests.single.url.path, '/rest/v1/rpc/deactivate_account');
    });

    test('deactivateAccount reports the blocker', () async {
      respond = (_) =>
          json({'message': 'active_sale', 'code': '55000'}, status: 400);
      await expectLater(
        repository.deactivateAccount(),
        throwsA(
          isA<AccountDeletionFailure>().having(
            (e) => e.blocker,
            'blocker',
            AccountDeletionBlocker.activeSale,
          ),
        ),
      );
    });

    test('reactivateAccount calls the function', () async {
      respond = (_) => http.Response('', 204, request: current);
      await repository.reactivateAccount();
      expect(requests.single.url.path, '/rest/v1/rpc/reactivate_account');
    });

    test('reactivateAccount throws AccountDeletionFailure', () async {
      respond = (_) => json({'message': 'x', 'code': '42501'}, status: 401);
      await expectLater(
        repository.reactivateAccount(),
        throwsA(isA<AccountDeletionFailure>()),
      );
    });
  });

  group('failures', () {
    test('have a readable toString', () {
      expect(
        const UpdateProfileFailure().toString(),
        'UpdateProfileFailure(null)',
      );
      expect(
        const AccountDeletionFailure(
          blocker: AccountDeletionBlocker.staffAccount,
        ).toString(),
        'AccountDeletionFailure(AccountDeletionBlocker.staffAccount, null)',
      );
      expect(AccountDeletionFailure.fromError(Exception('x')).blocker, isNull);
      expect(
        const ProfileNotFoundFailure('a').toString(),
        'ProfileNotFoundFailure(a)',
      );
      expect(const GetProfileFailure().toString(), 'GetProfileFailure(null)');
      expect(const UpdateRoleFailure().toString(), 'UpdateRoleFailure(null)');
    });
  });
}
