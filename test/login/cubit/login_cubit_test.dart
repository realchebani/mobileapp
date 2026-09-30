import 'dart:async';

import 'package:auth_repository/auth_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/login/cubit/cubit.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository;

class _MockTicker extends Mock implements Ticker;

void main() {
  const email = 'jane@example.com';
  const ready = LoginState(email: email, termsAccepted: true);
  const sent = LoginState(
    email: email,
    termsAccepted: true,
    status: LoginStatus.sent,
    sentTo: email,
    resendAvailableIn: LoginCubit.resendDelay,
  );

  late AuthRepository authRepository;
  late Ticker ticker;
  late StreamController<int> ticks;
  late StreamController<AuthLinkFailure> linkFailures;

  setUp(() {
    authRepository = _MockAuthRepository();
    ticker = _MockTicker();
    ticks = StreamController<int>();
    linkFailures = StreamController<AuthLinkFailure>();
    when(() => authRepository.linkFailures)
        .thenAnswer((_) => linkFailures.stream);
    when(() => ticker.tick(ticks: any(named: 'ticks')))
        .thenAnswer((_) => ticks.stream);
    when(() => authRepository.sendMagicLink(email: any(named: 'email')))
        .thenAnswer((_) async {});
  });

  tearDown(() {
    unawaited(ticks.close());
    unawaited(linkFailures.close());
  });

  LoginCubit buildCubit() =>
      LoginCubit(authRepository: authRepository, ticker: ticker);

  group('LoginCubit', () {
    test('initial state is LoginState()', () {
      expect(buildCubit().state, const LoginState());
    });

    test('uses the default ticker', () {
      expect(LoginCubit(authRepository: authRepository).state, isNotNull);
    });

    group('emailChanged', () {
      blocTest<LoginCubit, LoginState>(
        'updates the email',
        build: buildCubit,
        act: (cubit) => cubit.emailChanged(email),
        expect: () => const [LoginState(email: email)],
      );

      blocTest<LoginCubit, LoginState>(
        'clears a previous failure',
        build: buildCubit,
        seed: () => const LoginState(
          email: 'x',
          status: LoginStatus.failure,
          failureReason: LoginFailureReason.invalidEmail,
        ),
        act: (cubit) => cubit.emailChanged(email),
        expect: () => const [LoginState(email: email)],
      );

      blocTest<LoginCubit, LoginState>(
        'keeps a non-failure status',
        build: buildCubit,
        seed: () => sent,
        act: (cubit) => cubit.emailChanged('other@example.com'),
        expect: () => [sent.copyWith(email: 'other@example.com')],
      );
    });

    blocTest<LoginCubit, LoginState>(
      'termsToggled flips termsAccepted',
      build: buildCubit,
      act: (cubit) => cubit
        ..termsToggled()
        ..termsToggled(),
      expect: () => const [LoginState(termsAccepted: true), LoginState()],
    );

    group('submit', () {
      blocTest<LoginCubit, LoginState>(
        'does nothing when the email is invalid',
        build: buildCubit,
        seed: () => const LoginState(email: 'jane@', termsAccepted: true),
        act: (cubit) => cubit.submit(),
        expect: () => const <LoginState>[],
        verify: (_) => verifyNever(
          () => authRepository.sendMagicLink(email: any(named: 'email')),
        ),
      );

      blocTest<LoginCubit, LoginState>(
        'does nothing when the terms are not accepted',
        build: buildCubit,
        seed: () => const LoginState(email: email),
        act: (cubit) => cubit.submit(),
        expect: () => const <LoginState>[],
      );

      blocTest<LoginCubit, LoginState>(
        'does nothing while submitting',
        build: buildCubit,
        seed: () => ready.copyWith(status: LoginStatus.submitting),
        act: (cubit) => cubit.submit(),
        expect: () => const <LoginState>[],
      );

      blocTest<LoginCubit, LoginState>(
        'sends the link to the trimmed email and starts the countdown',
        build: buildCubit,
        seed: () => const LoginState(email: ' $email ', termsAccepted: true),
        act: (cubit) async {
          cubit.submit();
          await Future<void>.delayed(Duration.zero);
          ticks
            ..add(59)
            ..add(58);
        },
        expect: () => const [
          LoginState(
            email: ' $email ',
            termsAccepted: true,
            status: LoginStatus.submitting,
          ),
          LoginState(
            email: ' $email ',
            termsAccepted: true,
            status: LoginStatus.sent,
            sentTo: email,
            resendAvailableIn: 60,
          ),
          LoginState(
            email: ' $email ',
            termsAccepted: true,
            status: LoginStatus.sent,
            sentTo: email,
            resendAvailableIn: 59,
          ),
          LoginState(
            email: ' $email ',
            termsAccepted: true,
            status: LoginStatus.sent,
            sentTo: email,
            resendAvailableIn: 58,
          ),
        ],
        verify: (_) {
          verify(() => authRepository.sendMagicLink(email: email)).called(1);
          verify(() => ticker.tick(ticks: 60)).called(1);
        },
      );

      blocTest<LoginCubit, LoginState>(
        'emits failure with the reason on SendMagicLinkFailure',
        setUp: () =>
            when(() => authRepository.sendMagicLink(email: any(named: 'email')))
                .thenThrow(
                  const SendMagicLinkFailure(
                    SendMagicLinkFailureReason.rateLimited,
                  ),
                ),
        build: buildCubit,
        seed: () => ready,
        act: (cubit) => cubit.submit(),
        expect: () => [
          ready.copyWith(status: LoginStatus.submitting),
          ready.copyWith(
            status: LoginStatus.failure,
            failureReason: () => LoginFailureReason.rateLimited,
          ),
        ],
      );

      final error = Exception('oops');
      blocTest<LoginCubit, LoginState>(
        'emits an unknown failure and adds unexpected errors',
        setUp: () =>
            when(() => authRepository.sendMagicLink(email: any(named: 'email')))
                .thenThrow(error),
        build: buildCubit,
        seed: () => ready,
        act: (cubit) => cubit.submit(),
        expect: () => [
          ready.copyWith(status: LoginStatus.submitting),
          ready.copyWith(
            status: LoginStatus.failure,
            failureReason: () => LoginFailureReason.unknown,
          ),
        ],
        errors: () => [error],
      );

      blocTest<LoginCubit, LoginState>(
        'emits nothing more when closed while sending (success)',
        setUp: () =>
            when(() => authRepository.sendMagicLink(email: any(named: 'email')))
                .thenAnswer((_) => Future<void>.delayed(Duration.zero)),
        build: buildCubit,
        seed: () => ready,
        act: (cubit) async {
          cubit.submit();
          await cubit.close();
        },
        expect: () => [ready.copyWith(status: LoginStatus.submitting)],
      );

      blocTest<LoginCubit, LoginState>(
        'emits nothing more when closed while sending (failure)',
        setUp: () =>
            when(() => authRepository.sendMagicLink(email: any(named: 'email')))
                .thenAnswer(
                  (_) => Future<void>.delayed(
                    Duration.zero,
                    () => throw const SendMagicLinkFailure(
                      SendMagicLinkFailureReason.network,
                    ),
                  ),
                ),
        build: buildCubit,
        seed: () => ready,
        act: (cubit) async {
          cubit.submit();
          await cubit.close();
        },
        expect: () => [ready.copyWith(status: LoginStatus.submitting)],
      );
    });

    group('resend', () {
      blocTest<LoginCubit, LoginState>(
        'does nothing before a link was sent',
        build: buildCubit,
        seed: () => ready,
        act: (cubit) => cubit.resend(),
        expect: () => const <LoginState>[],
      );

      blocTest<LoginCubit, LoginState>(
        'does nothing during the countdown',
        build: buildCubit,
        seed: () => sent,
        act: (cubit) => cubit.resend(),
        expect: () => const <LoginState>[],
      );

      blocTest<LoginCubit, LoginState>(
        'sends the link again to sentTo and restarts the countdown',
        build: buildCubit,
        seed: () =>
            sent.copyWith(email: 'edited@example.com', resendAvailableIn: 0),
        act: (cubit) => cubit.resend(),
        expect: () => [
          sent.copyWith(
            email: 'edited@example.com',
            status: LoginStatus.submitting,
            resendAvailableIn: 0,
          ),
          sent.copyWith(email: 'edited@example.com'),
        ],
        verify: (_) =>
            verify(() => authRepository.sendMagicLink(email: email)).called(1),
      );

      blocTest<LoginCubit, LoginState>(
        'keeps sentTo when resending fails',
        setUp: () =>
            when(
              () => authRepository.sendMagicLink(email: any(named: 'email')),
            ).thenThrow(
              const SendMagicLinkFailure(SendMagicLinkFailureReason.network),
            ),
        build: buildCubit,
        seed: () => sent.copyWith(resendAvailableIn: 0),
        act: (cubit) => cubit.resend(),
        expect: () => [
          sent.copyWith(status: LoginStatus.submitting, resendAvailableIn: 0),
          sent.copyWith(
            status: LoginStatus.failure,
            failureReason: () => LoginFailureReason.network,
            resendAvailableIn: 0,
          ),
        ],
      );
    });

    blocTest<LoginCubit, LoginState>(
      'editEmail goes back to initial, keeping email and terms, '
      'and stops the countdown',
      build: buildCubit,
      seed: () => ready,
      act: (cubit) async {
        cubit.submit();
        await Future<void>.delayed(Duration.zero);
        cubit.editEmail();
        ticks.add(59);
      },
      expect: () => [
        ready.copyWith(status: LoginStatus.submitting),
        sent,
        ready,
      ],
    );

    group('maps send failures', () {
      const reasons = {
        SendMagicLinkFailureReason.invalidEmail:
            LoginFailureReason.invalidEmail,
        SendMagicLinkFailureReason.notAuthorized:
            LoginFailureReason.notAuthorized,
        SendMagicLinkFailureReason.network: LoginFailureReason.network,
        SendMagicLinkFailureReason.unknown: LoginFailureReason.unknown,
      };
      for (final MapEntry(key: from, value: to) in reasons.entries) {
        blocTest<LoginCubit, LoginState>(
          '$from to $to',
          setUp: () => when(
            () => authRepository.sendMagicLink(email: any(named: 'email')),
          ).thenThrow(SendMagicLinkFailure(from)),
          build: buildCubit,
          seed: () => ready,
          act: (cubit) => cubit.submit(),
          skip: 1,
          expect: () => [
            ready.copyWith(
              status: LoginStatus.failure,
              failureReason: () => to,
            ),
          ],
        );
      }
    });

    blocTest<LoginCubit, LoginState>(
      'restarts the countdown when a resend is rate limited',
      setUp: () =>
          when(
            () => authRepository.sendMagicLink(email: any(named: 'email')),
          ).thenThrow(
            const SendMagicLinkFailure(SendMagicLinkFailureReason.rateLimited),
          ),
      build: buildCubit,
      seed: () => sent.copyWith(resendAvailableIn: 0),
      act: (cubit) async {
        cubit.resend();
        await Future<void>.delayed(Duration.zero);
        ticks.add(59);
      },
      expect: () => [
        sent.copyWith(status: LoginStatus.submitting, resendAvailableIn: 0),
        sent.copyWith(
          status: LoginStatus.failure,
          failureReason: () => LoginFailureReason.rateLimited,
        ),
        sent.copyWith(
          status: LoginStatus.failure,
          failureReason: () => LoginFailureReason.rateLimited,
          resendAvailableIn: 59,
        ),
      ],
      verify: (_) => verify(() => ticker.tick(ticks: 60)).called(1),
    );

    group('editEmail during a send', () {
      late Completer<void> completer;

      setUp(() {
        completer = Completer<void>();
        when(() => authRepository.sendMagicLink(email: any(named: 'email')))
            .thenAnswer((_) => completer.future);
      });

      blocTest<LoginCubit, LoginState>(
        'ignores the send result when it succeeds',
        build: buildCubit,
        seed: () => ready,
        act: (cubit) async {
          cubit
            ..submit()
            ..editEmail();
          completer.complete();
          await Future<void>.delayed(Duration.zero);
        },
        expect: () => [ready.copyWith(status: LoginStatus.submitting), ready],
        verify: (_) =>
            verifyNever(() => ticker.tick(ticks: any(named: 'ticks'))),
      );

      blocTest<LoginCubit, LoginState>(
        'ignores the send result when it fails',
        setUp: () =>
            when(() => authRepository.sendMagicLink(email: any(named: 'email')))
                .thenAnswer(
                  (_) => Future<void>.delayed(
                    Duration.zero,
                    () => throw const SendMagicLinkFailure(
                      SendMagicLinkFailureReason.rateLimited,
                    ),
                  ),
                ),
        build: buildCubit,
        seed: () => sent.copyWith(resendAvailableIn: 0),
        act: (cubit) async {
          cubit
            ..resend()
            ..editEmail();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        expect: () => [
          sent.copyWith(status: LoginStatus.submitting, resendAvailableIn: 0),
          ready,
        ],
      );

      blocTest<LoginCubit, LoginState>(
        'still handles a new send',
        build: buildCubit,
        seed: () => ready,
        act: (cubit) async {
          cubit
            ..submit()
            ..editEmail()
            ..submit();
          completer.complete();
          await Future<void>.delayed(Duration.zero);
        },
        expect: () => [
          ready.copyWith(status: LoginStatus.submitting),
          ready,
          ready.copyWith(status: LoginStatus.submitting),
          sent,
        ],
      );
    });

    group('link failures', () {
      blocTest<LoginCubit, LoginState>(
        'are ignored before a link was sent',
        build: buildCubit,
        seed: () => ready,
        act: (_) => linkFailures.add(
          const AuthLinkFailure(AuthLinkFailureReason.expired),
        ),
        expect: () => const <LoginState>[],
      );

      blocTest<LoginCubit, LoginState>(
        'emit linkExpired for expired links',
        build: buildCubit,
        seed: () => sent,
        act: (_) => linkFailures.add(
          const AuthLinkFailure(AuthLinkFailureReason.expired),
        ),
        expect: () => [
          sent.copyWith(
            status: LoginStatus.failure,
            failureReason: () => LoginFailureReason.linkExpired,
          ),
        ],
      );

      for (final reason in [
        AuthLinkFailureReason.invalid,
        AuthLinkFailureReason.unknown,
      ]) {
        blocTest<LoginCubit, LoginState>(
          'emit linkInvalid for $reason',
          build: buildCubit,
          seed: () => sent,
          act: (_) => linkFailures.add(AuthLinkFailure(reason)),
          expect: () => [
            sent.copyWith(
              status: LoginStatus.failure,
              failureReason: () => LoginFailureReason.linkInvalid,
            ),
          ],
        );
      }
    });
  });

  group('LoginState', () {
    test('validates emails', () {
      const valid = ['a@b.co', 'jane.doe+tag@sub.example.fr', ' x@y.io '];
      const invalid = [
        '',
        'jane',
        'jane@',
        'jane@example',
        'a b@c.de',
        '@b.co',
      ];
      for (final email in valid) {
        expect(LoginState(email: email).isEmailValid, isTrue, reason: email);
      }
      for (final email in invalid) {
        expect(LoginState(email: email).isEmailValid, isFalse, reason: email);
      }
    });
  });
}
