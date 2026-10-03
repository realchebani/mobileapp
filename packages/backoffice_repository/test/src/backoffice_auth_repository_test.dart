import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

class _MockAuth extends Mock implements GoTrueClient;

class _MockMfa extends Mock implements GoTrueMFAApi;

Factor _factor(String id, FactorStatus status) => Factor(
  id: id,
  friendlyName: id,
  factorType: FactorType.totp,
  status: status,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late _MockAuth auth;
  late _MockMfa mfa;
  late BackOfficeAuthRepository repository;

  setUp(() {
    auth = _MockAuth();
    mfa = _MockMfa();
    when(() => auth.mfa).thenReturn(mfa);
    repository = BackOfficeAuthRepository(auth: auth);
  });

  test('session state', () {
    when(() => auth.onAuthStateChange).thenAnswer((_) => const Stream.empty());
    when(() => auth.currentSession).thenReturn(null);
    when(() => auth.currentUser).thenReturn(null);
    expect(repository.changes, isA<Stream<AuthState>>());
    expect(repository.isSignedIn, isFalse);
    expect(repository.email, isNull);
  });

  test('sendMagicLink trims the e-mail and sets the redirect', () async {
    when(
      () => auth.signInWithOtp(
        email: any(named: 'email'),
        emailRedirectTo: any(named: 'emailRedirectTo'),
      ),
    ).thenAnswer((_) async {});
    await repository.sendMagicLink(' a@b.c ', redirectTo: 'http://x/');
    verify(
      () => auth.signInWithOtp(email: 'a@b.c', emailRedirectTo: 'http://x/'),
    ).called(1);
  });

  test('signInWithPassword and signOut', () async {
    when(
      () => auth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => AuthResponse());
    when(() => auth.signOut()).thenAnswer((_) async {});
    await repository.signInWithPassword(' a@b.c', 'pw');
    await repository.signOut();
    verify(() => auth.signInWithPassword(email: 'a@b.c', password: 'pw'))
        .called(1);
    verify(() => auth.signOut()).called(1);
  });

  test('mfaStatus', () async {
    when(() => mfa.getAuthenticatorAssuranceLevel()).thenReturn(
      const AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: AuthenticatorAssuranceLevels.aal1,
        nextLevel: AuthenticatorAssuranceLevels.aal2,
        currentAuthenticationMethods: [],
      ),
    );
    when(() => mfa.listFactors()).thenAnswer(
      (_) async => AuthMFAListFactorsResponse(
        all: [_factor('f1', FactorStatus.verified)],
        totp: [_factor('f1', FactorStatus.verified)],
        phone: const [],
      ),
    );
    final status = await repository.mfaStatus();
    expect(status, const MfaStatus(passed: false, factorId: 'f1'));
    expect(status.enrolled, isTrue);
    expect(const MfaStatus(passed: true).enrolled, isFalse);
  });

  test('enrollTotp removes unfinished factors first', () async {
    when(() => mfa.listFactors()).thenAnswer(
      (_) async => AuthMFAListFactorsResponse(
        all: [
          _factor('old', FactorStatus.unverified),
          _factor('ok', FactorStatus.verified),
        ],
        totp: [_factor('ok', FactorStatus.verified)],
        phone: const [],
      ),
    );
    when(() => mfa.unenroll(any()))
        .thenAnswer((_) async => const AuthMFAUnenrollResponse(id: 'old'));
    when(
      () => mfa.enroll(
        issuer: any(named: 'issuer'),
        friendlyName: any(named: 'friendlyName'),
      ),
    ).thenAnswer(
      (_) async => const AuthMFAEnrollResponse(
        id: 'new',
        type: FactorType.totp,
        totp: TOTPEnrollment(qrCode: '<svg/>', secret: 'S3CR3T', uri: 'otp'),
      ),
    );
    final enrollment = await repository.enrollTotp();
    expect(
      enrollment,
      const TotpEnrollment(
        factorId: 'new',
        qrCodeSvg: '<svg/>',
        secret: 'S3CR3T',
      ),
    );
    verify(() => mfa.unenroll('old')).called(1);
    verifyNever(() => mfa.unenroll('ok'));
  });

  test('verifyTotp and its failures', () async {
    when(
      () => mfa.challengeAndVerify(
        factorId: any(named: 'factorId'),
        code: any(named: 'code'),
      ),
    ).thenThrow(const AuthException('Invalid', statusCode: '422', code: 'x'));
    await expectLater(
      repository.verifyTotp('f1', ' 123456 '),
      throwsA(
        isA<BackOfficeAuthFailure>().having(
          (f) => f.reason,
          'reason',
          BackOfficeAuthFailureReason.invalidCode,
        ),
      ),
    );
    verify(() => mfa.challengeAndVerify(factorId: 'f1', code: '123456'))
        .called(1);
  });

  test('BackOfficeAuthFailure.from', () {
    expect(
      BackOfficeAuthFailure.from(const AuthException('x', statusCode: '429'))
          .reason,
      BackOfficeAuthFailureReason.rateLimited,
    );
    expect(
      BackOfficeAuthFailure.from(
        const AuthException('x', code: 'mfa_verification_failed'),
      ).reason,
      BackOfficeAuthFailureReason.invalidCode,
    );
    expect(
      BackOfficeAuthFailure.from(const AuthException('x')).reason,
      BackOfficeAuthFailureReason.unknown,
    );
    expect(
      BackOfficeAuthFailure.from(Exception('x')).reason,
      BackOfficeAuthFailureReason.unknown,
    );
    expect(
      '${BackOfficeAuthFailure.from(Exception('x'))}',
      contains('unknown'),
    );
  });
}
