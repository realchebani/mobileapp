import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/mfa/mfa.dart';

import '../helpers/helpers.dart';

const _qr =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"> '
    '<rect width="10" height="10"/></svg>';
const _enrollment = TotpEnrollment(
  factorId: 'f-new',
  qrCodeSvg: _qr,
  secret: 'ABCDEF',
);

void main() {
  late MockBackOfficeAuthRepository auth;

  setUp(() {
    auth = MockBackOfficeAuthRepository();
    when(() => auth.enrollTotp()).thenAnswer((_) async => _enrollment);
    when(() => auth.verifyTotp(any(), any())).thenAnswer((_) async {});
  });

  group(MfaCubit, () {
    blocTest<MfaCubit, MfaState>(
      'enrols when there is no factor',
      build: () => MfaCubit(auth: auth, factorId: null),
      act: (cubit) => cubit.start(),
      expect: () => [
        const MfaState(status: MfaStatusValue.loading),
        const MfaState(factorId: 'f-new', enrollment: _enrollment),
      ],
    );

    blocTest<MfaCubit, MfaState>(
      'keeps the verified factor',
      build: () => MfaCubit(auth: auth, factorId: 'f1'),
      act: (cubit) => cubit.start(),
      expect: () => <MfaState>[],
    );

    blocTest<MfaCubit, MfaState>(
      'enrolment failure',
      setUp: () => when(() => auth.enrollTotp()).thenThrow(
        const BackOfficeAuthFailure(BackOfficeAuthFailureReason.unknown),
      ),
      build: () => MfaCubit(auth: auth, factorId: null),
      act: (cubit) => cubit.start(),
      skip: 1,
      expect: () => [const MfaState(status: MfaStatusValue.failure)],
    );

    blocTest<MfaCubit, MfaState>(
      'verifies a 6-digit code',
      build: () => MfaCubit(auth: auth, factorId: 'f1'),
      act: (cubit) async {
        cubit.codeChanged('12');
        expect(await cubit.verify(), isFalse);
        cubit.codeChanged('123456');
        expect(await cubit.verify(), isTrue);
      },
      expect: () => [
        const MfaState(factorId: 'f1', code: '12'),
        const MfaState(
          factorId: 'f1',
          code: '12',
          status: MfaStatusValue.invalidCode,
        ),
        const MfaState(factorId: 'f1', code: '123456'),
        const MfaState(
          factorId: 'f1',
          code: '123456',
          status: MfaStatusValue.verifying,
        ),
        const MfaState(
          factorId: 'f1',
          code: '123456',
          status: MfaStatusValue.verified,
        ),
      ],
    );

    blocTest<MfaCubit, MfaState>(
      'wrong code and other failures',
      setUp: () {
        var calls = 0;
        when(() => auth.verifyTotp(any(), any())).thenAnswer(
          (_) async => throw BackOfficeAuthFailure(
            calls++ == 0
                ? BackOfficeAuthFailureReason.invalidCode
                : BackOfficeAuthFailureReason.unknown,
          ),
        );
      },
      build: () => MfaCubit(auth: auth, factorId: 'f1'),
      seed: () => const MfaState(factorId: 'f1', code: '123456'),
      act: (cubit) async {
        await cubit.verify();
        await cubit.verify();
      },
      skip: 1,
      expect: () => [
        const MfaState(
          factorId: 'f1',
          code: '123456',
          status: MfaStatusValue.invalidCode,
        ),
        const MfaState(
          factorId: 'f1',
          code: '123456',
          status: MfaStatusValue.verifying,
        ),
        const MfaState(
          factorId: 'f1',
          code: '123456',
          status: MfaStatusValue.failure,
        ),
      ],
    );

    test('no factor, nothing to verify', () async {
      expect(await MfaCubit(auth: auth, factorId: null).verify(), isFalse);
    });
  });

  group(MfaPage, () {
    MockSessionCubit session(String? factorId) {
      final cubit = MockSessionCubit();
      whenListen(
        cubit,
        const Stream<SessionState>.empty(),
        initialState: SessionState(
          status: SessionStatus.mfa,
          mfa: MfaStatus(passed: false, factorId: factorId),
        ),
      );
      when(cubit.refresh).thenAnswer((_) async {});
      when(cubit.signOut).thenAnswer((_) async {});
      return cubit;
    }

    testWidgets('first sign-in: QR code then the code', (tester) async {
      tester.useDesktopSurface();
      final s = session(null);
      await tester.pumpBo(const MfaPage(), auth: auth, session: s);
      await tester.pump();
      expect(find.text('Double authentification'), findsOneWidget);
      expect(find.text('ABCDEF'), findsOneWidget);
      await tester.enterText(find.byType(EditableText).last, '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      verify(() => auth.verifyTotp('f-new', '123456')).called(1);
      verify(s.refresh).called(1);
      await tester.tap(find.text('Se déconnecter'));
      verify(s.signOut).called(1);
    });

    testWidgets('known factor: the code only, with errors', (tester) async {
      tester.useDesktopSurface();
      when(() => auth.verifyTotp(any(), any())).thenThrow(
        const BackOfficeAuthFailure(BackOfficeAuthFailureReason.invalidCode),
      );
      await tester.pumpBo(const MfaPage(), auth: auth, session: session('f1'));
      await tester.pump();
      expect(find.textContaining('Saisissez le code'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.tap(find.text('Valider'));
      await tester.pump();
      expect(find.textContaining('Code incorrect'), findsOneWidget);
    });

    testWidgets('enrolment failure offers to retry', (tester) async {
      tester.useDesktopSurface();
      when(() => auth.enrollTotp()).thenThrow(
        const BackOfficeAuthFailure(BackOfficeAuthFailureReason.unknown),
      );
      await tester.pumpBo(const MfaPage(), auth: auth, session: session(null));
      await tester.pump();
      expect(find.textContaining('La vérification a échoué'), findsOneWidget);
      when(() => auth.enrollTotp()).thenAnswer((_) async => _enrollment);
      await tester.tap(find.text('Configurer l’application'));
      await tester.pump();
      expect(find.text('ABCDEF'), findsOneWidget);
    });
  });
}
