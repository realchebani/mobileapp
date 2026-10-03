import 'dart:async';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/app/view/shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/helpers.dart';

void main() {
  late MockBackOfficeAuthRepository auth;
  late MockBackOfficeRepository repository;
  late StreamController<AuthState> changes;

  setUp(() {
    auth = MockBackOfficeAuthRepository();
    repository = MockBackOfficeRepository();
    changes = StreamController<AuthState>.broadcast();
    when(() => auth.changes).thenAnswer((_) => changes.stream);
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(
      () => repository.listDossiers(
        statuses: any(named: 'statuses'),
        scope: any(named: 'scope'),
        search: any(named: 'search'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => [summary()]);
  });

  tearDown(() => changes.close());

  Future<void> pumpApp(WidgetTester tester, {String location = '/'}) async {
    tester.useDesktopSurface();
    await tester.pumpWidget(
      App(
        authRepository: auth,
        repository: repository,
        config: const BackOfficeConfig(authRedirectUrl: 'http://x/'),
        browser: FakeBrowser(),
        initialLocation: location,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed out: the sign-in page', (tester) async {
    when(() => auth.isSignedIn).thenReturn(false);
    await pumpApp(tester);
    expect(find.text('Connexion de l’équipe'), findsOneWidget);
  });

  testWidgets('a member reaches the queue and the admin pages', (tester) async {
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.mfaStatus())
        .thenAnswer((_) async => const MfaStatus(passed: true, factorId: 'f1'));
    when(() => repository.me()).thenAnswer((_) async => adminMe);
    await pumpApp(tester);
    expect(find.text('Chaponost 69630'), findsOneWidget);
    expect(find.text('Maxime C.'), findsOneWidget);

    await tester.tap(find.text('Équipe'));
    await tester.pumpAndSettle();
    expect(find.byType(BoShell), findsOneWidget);
    await tester.tap(find.text('Journal'));
    await tester.pumpAndSettle();

    when(() => auth.isSignedIn).thenReturn(false);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion de l’équipe'), findsOneWidget);
  });

  testWidgets('a dossier URL opens its first tab', (tester) async {
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.mfaStatus())
        .thenAnswer((_) async => const MfaStatus(passed: true, factorId: 'f1'));
    when(() => repository.me()).thenAnswer((_) async => expertMe);
    await pumpApp(tester, location: '/dossiers/p1');
    expect(find.byType(BoShell), findsOneWidget);
    expect(find.text('Équipe'), findsNothing);
  });

  testWidgets('gates: denied, unavailable', (tester) async {
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.mfaStatus())
        .thenAnswer((_) async => const MfaStatus(passed: true, factorId: 'f1'));
    when(() => repository.me()).thenAnswer(
      (_) async => const StaffMe(userId: 'u', email: 'x@y.fr', aal2: true),
    );
    await pumpApp(tester);
    expect(find.text('Accès refusé'), findsOneWidget);
    expect(find.textContaining('x@y.fr'), findsOneWidget);

    when(() => auth.mfaStatus()).thenThrow(Exception('offline'));
    changes.add(const AuthState(AuthChangeEvent.userUpdated, null));
    await tester.pumpAndSettle();
    expect(find.text('Back-office indisponible'), findsOneWidget);
    when(() => auth.mfaStatus())
        .thenAnswer((_) async => const MfaStatus(passed: true, factorId: 'f1'));
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.text('Accès refusé'), findsOneWidget);
    when(() => auth.isSignedIn).thenReturn(false);
    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    expect(find.text('Connexion de l’équipe'), findsOneWidget);
  });

  testWidgets('loading gate while the session is checked', (tester) async {
    final pending = Completer<MfaStatus>();
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.mfaStatus()).thenAnswer((_) => pending.future);
    tester.useDesktopSurface();
    await tester.pumpWidget(
      App(
        authRepository: auth,
        repository: repository,
        config: const BackOfficeConfig(authRedirectUrl: 'http://x/'),
        browser: FakeBrowser(),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const MfaStatus(passed: false));
    when(() => auth.enrollTotp()).thenAnswer(
      (_) async => const TotpEnrollment(
        factorId: 'f',
        qrCodeSvg: '<svg xmlns="http://www.w3.org/2000/svg"/>',
        secret: 'S',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Double authentification'), findsOneWidget);
  });

  testWidgets('narrow windows get a message', (tester) async {
    tester.useDesktopSurface(const Size(900, 700));
    await tester.pumpBo(
      const BoShell(location: '/dossiers', child: Text('page')),
    );
    expect(find.text('Écran trop étroit'), findsOneWidget);
    expect(find.text('page'), findsNothing);
  });
}
