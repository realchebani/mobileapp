import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:gotrue/gotrue.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient;

class _MockSession extends Mock implements Session;

class _MockUser extends Mock implements User;

void main() {
  const redirectUrl = 'fr.realesty.mobile.dev://login-callback';
  const email = 'jane@example.com';

  late GoTrueClient auth;
  late AuthRepository repository;

  User buildUser({String id = 'user-id', String? email = email}) {
    final user = _MockUser();
    when(() => user.id).thenReturn(id);
    when(() => user.email).thenReturn(email);
    return user;
  }

  Session buildSession(User user) {
    final session = _MockSession();
    when(() => session.user).thenReturn(user);
    return session;
  }

  setUp(() {
    auth = _MockGoTrueClient();
    repository = AuthRepository(auth: auth, redirectUrl: redirectUrl);
  });

  group('AuthRepository', () {
    group('user', () {
      test('emits null when there is no session', () {
        when(() => auth.onAuthStateChange).thenAnswer(
          (_) => Stream.value(
            const AuthState(AuthChangeEvent.initialSession, null),
          ),
        );
        expect(repository.user, emitsInOrder(<Object?>[null, emitsDone]));
      });

      test('maps sessions to AuthUser, dropping duplicates and errors', () {
        final session = buildSession(buildUser());
        final controller = StreamController<AuthState>();
        when(() => auth.onAuthStateChange).thenAnswer((_) => controller.stream);

        expect(
          repository.user,
          emitsInOrder(<Object?>[
            null,
            const AuthUser(id: 'user-id', email: email),
            null,
            emitsDone,
          ]),
        );

        controller
          ..add(const AuthState(AuthChangeEvent.initialSession, null))
          ..add(AuthState(AuthChangeEvent.signedIn, session))
          ..add(AuthState(AuthChangeEvent.tokenRefreshed, session))
          ..addError(const AuthException('refresh failed'))
          ..add(const AuthState(AuthChangeEvent.signedOut, null));
        unawaited(controller.close());
      });
    });

    group('linkFailures', () {
      test('emits classified link errors only', () {
        final controller = StreamController<AuthState>();
        when(() => auth.onAuthStateChange).thenAnswer((_) => controller.stream);

        expect(
          repository.linkFailures.map((f) => f.reason),
          emitsInOrder(<Object?>[
            AuthLinkFailureReason.expired,
            AuthLinkFailureReason.invalid,
            emitsDone,
          ]),
        );

        controller
          ..add(const AuthState(AuthChangeEvent.initialSession, null))
          ..addError(AuthRetryableFetchException())
          ..addError(
            const AuthException(
              'Email link is invalid or has expired',
              statusCode: 'otp_expired',
              code: 'access_denied',
            ),
          )
          ..addError(
            const AuthException(
              'Code verifier could not be found in local storage.',
            ),
          );
        unawaited(controller.close());
      });
    });

    group('currentUser', () {
      test('returns null when signed out', () {
        when(() => auth.currentUser).thenReturn(null);
        expect(repository.currentUser, isNull);
      });

      test('returns the signed-in user', () {
        final user = buildUser(email: null);
        when(() => auth.currentUser).thenReturn(user);
        expect(repository.currentUser, const AuthUser(id: 'user-id'));
      });
    });

    group('sendMagicLink', () {
      When<Future<void>> stubOtp() => when(
        () => auth.signInWithOtp(
          email: any(named: 'email'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
          shouldCreateUser: any(named: 'shouldCreateUser'),
        ),
      );

      test('calls signInWithOtp with the trimmed email and redirect', () async {
        stubOtp().thenAnswer((_) async {});
        await repository.sendMagicLink(email: '  $email ');
        verify(
          () => auth.signInWithOtp(
            email: email,
            emailRedirectTo: redirectUrl,
            shouldCreateUser: true,
          ),
        ).called(1);
      });

      Future<void> expectReason(
        Object error,
        SendMagicLinkFailureReason reason,
      ) async {
        stubOtp().thenThrow(error);
        await expectLater(
          repository.sendMagicLink(email: email),
          throwsA(
            isA<SendMagicLinkFailure>()
                .having((f) => f.reason, 'reason', reason)
                .having((f) => f.error, 'error', error),
          ),
        );
      }

      test('throws rateLimited on HTTP 429', () async {
        await expectReason(
          const AuthApiException('slow down', statusCode: '429'),
          SendMagicLinkFailureReason.rateLimited,
        );
      });

      test('throws rateLimited on over_email_send_rate_limit', () async {
        await expectReason(
          const AuthApiException(
            'slow down',
            statusCode: '400',
            code: 'over_email_send_rate_limit',
          ),
          SendMagicLinkFailureReason.rateLimited,
        );
      });

      test('throws rateLimited on over_request_rate_limit', () async {
        await expectReason(
          const AuthApiException('slow down', code: 'over_request_rate_limit'),
          SendMagicLinkFailureReason.rateLimited,
        );
      });

      test('throws invalidEmail on email_address_invalid', () async {
        await expectReason(
          const AuthApiException(
            'bad email',
            statusCode: '400',
            code: 'email_address_invalid',
          ),
          SendMagicLinkFailureReason.invalidEmail,
        );
      });

      test('throws invalidEmail on validation_failed', () async {
        await expectReason(
          const AuthApiException('bad email', code: 'validation_failed'),
          SendMagicLinkFailureReason.invalidEmail,
        );
      });

      test('throws network when the request could not be made', () async {
        await expectReason(
          AuthRetryableFetchException(message: 'SocketException'),
          SendMagicLinkFailureReason.network,
        );
      });

      test('throws network on server errors', () async {
        await expectReason(
          AuthRetryableFetchException(statusCode: '503'),
          SendMagicLinkFailureReason.network,
        );
      });

      test('throws notAuthorized on email_address_not_authorized', () async {
        await expectReason(
          const AuthApiException(
            'Email address not authorized',
            statusCode: '400',
            code: 'email_address_not_authorized',
          ),
          SendMagicLinkFailureReason.notAuthorized,
        );
      });

      test('throws unknown on other auth errors', () async {
        await expectReason(
          const AuthApiException('nope', statusCode: '400'),
          SendMagicLinkFailureReason.unknown,
        );
      });

      test('throws unknown on non-auth errors', () async {
        await expectReason(
          Exception('oops'),
          SendMagicLinkFailureReason.unknown,
        );
      });
    });

    group('signInWithPassword', () {
      const password = 'secret';

      When<Future<AuthResponse>> stubSignIn() => when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );

      test('calls signInWithPassword with the trimmed email', () async {
        stubSignIn().thenAnswer((_) async => AuthResponse());
        await repository.signInWithPassword(
          email: ' $email ',
          password: password,
        );
        verify(() => auth.signInWithPassword(email: email, password: password))
            .called(1);
      });

      Future<void> expectReason(
        Object error,
        SignInWithPasswordFailureReason reason,
      ) async {
        stubSignIn().thenThrow(error);
        await expectLater(
          repository.signInWithPassword(email: email, password: password),
          throwsA(
            isA<SignInWithPasswordFailure>()
                .having((f) => f.reason, 'reason', reason)
                .having((f) => f.error, 'error', error),
          ),
        );
      }

      test('throws invalidCredentials on invalid_credentials', () async {
        await expectReason(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
          SignInWithPasswordFailureReason.invalidCredentials,
        );
      });

      test('throws network when the request could not be made', () async {
        await expectReason(
          AuthRetryableFetchException(message: 'SocketException'),
          SignInWithPasswordFailureReason.network,
        );
      });

      test('throws unknown on other auth errors', () async {
        await expectReason(
          const AuthApiException('nope', code: 'email_not_confirmed'),
          SignInWithPasswordFailureReason.unknown,
        );
      });

      test('throws unknown on non-auth errors', () async {
        await expectReason(
          Exception('oops'),
          SignInWithPasswordFailureReason.unknown,
        );
      });
    });

    group('signOut', () {
      test('calls signOut on the auth client', () async {
        when(() => auth.signOut()).thenAnswer((_) async {});
        await repository.signOut();
        verify(() => auth.signOut()).called(1);
      });

      test('revokes every session when asked to', () async {
        when(() => auth.signOut(scope: SignOutScope.global))
            .thenAnswer((_) async {});
        await repository.signOut(everywhere: true);
        verify(() => auth.signOut(scope: SignOutScope.global)).called(1);
      });

      test('throws SignOutFailure on error', () async {
        final error = Exception('oops');
        when(() => auth.signOut()).thenThrow(error);
        await expectLater(
          repository.signOut(),
          throwsA(isA<SignOutFailure>().having((f) => f.error, 'error', error)),
        );
      });
    });
  });

  group('SendMagicLinkFailure', () {
    test('has a readable toString', () {
      expect(
        const SendMagicLinkFailure(SendMagicLinkFailureReason.network)
            .toString(),
        'SendMagicLinkFailure(SendMagicLinkFailureReason.network, null)',
      );
    });
  });

  group('SignInWithPasswordFailure', () {
    test('has a readable toString', () {
      expect(
        const SignInWithPasswordFailure(SignInWithPasswordFailureReason.network)
            .toString(),
        'SignInWithPasswordFailure('
        'SignInWithPasswordFailureReason.network, null)',
      );
    });
  });

  group('AuthLinkFailure.tryFromError', () {
    AuthLinkFailureReason? reasonOf(Object error) =>
        AuthLinkFailure.tryFromError(error)?.reason;

    test('ignores errors unrelated to links', () {
      expect(reasonOf(Exception('oops')), isNull);
      expect(reasonOf(AuthRetryableFetchException()), isNull);
      expect(reasonOf(AuthSessionMissingException()), isNull);
      expect(
        reasonOf(const AuthException('x', code: 'session_expired')),
        isNull,
      );
      expect(
        reasonOf(const AuthApiException('x', code: 'refresh_token_not_found')),
        isNull,
      );
    });

    test('detects expired links', () {
      expect(
        reasonOf(const AuthApiException('x', code: 'flow_state_expired')),
        AuthLinkFailureReason.expired,
      );
      expect(
        reasonOf(
          const AuthException(
            'x',
            statusCode: 'otp_expired',
            code: 'access_denied',
          ),
        ),
        AuthLinkFailureReason.expired,
      );
    });

    test('detects invalid links', () {
      expect(
        reasonOf(const AuthPKCEGrantCodeExchangeError('No code detected.')),
        AuthLinkFailureReason.invalid,
      );
      expect(
        reasonOf(const AuthApiException('x', code: 'flow_state_not_found')),
        AuthLinkFailureReason.invalid,
      );
      expect(
        reasonOf(const AuthException('x', code: 'access_denied')),
        AuthLinkFailureReason.invalid,
      );
    });

    test('returns unknown for other auth errors', () {
      expect(
        reasonOf(const AuthException('Error in URL')),
        AuthLinkFailureReason.unknown,
      );
    });

    test('has a readable toString', () {
      expect(
        const AuthLinkFailure(AuthLinkFailureReason.expired).toString(),
        'AuthLinkFailure(AuthLinkFailureReason.expired, null)',
      );
    });
  });

  group('SignOutFailure', () {
    test('has a readable toString', () {
      expect(const SignOutFailure().toString(), 'SignOutFailure(null)');
    });
  });
}
