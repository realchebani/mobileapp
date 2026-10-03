import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/l10n/l10n.dart';
import 'package:realesty_ui/realesty_ui.dart';

class MockBackOfficeRepository extends Mock implements BackOfficeRepository;

class MockBackOfficeAuthRepository extends Mock
    implements BackOfficeAuthRepository;

class MockGoRouter extends Mock implements GoRouter;

class MockSessionCubit extends MockCubit<SessionState> implements SessionCubit;

class FakeBrowser implements Browser {
  final List<String> opened = <String>[];
  final List<(String, String)> saved = [];
  PickedFile? nextPdf;

  @override
  Future<void> open(String url) async => opened.add(url);

  @override
  Future<PickedFile?> pickPdf() async => nextPdf;

  @override
  Future<void> saveText(
    String fileName,
    String text, {
    String mimeType = 'text/csv',
  }) async => saved.add((fileName, text));
}

const Set<BackOfficeCapability> adminCapabilities = {
  BackOfficeCapability.queueAll,
  BackOfficeCapability.assign,
  BackOfficeCapability.take,
  BackOfficeCapability.startReview,
  BackOfficeCapability.editDraft,
  BackOfficeCapability.certify,
  BackOfficeCapability.attachReport,
  BackOfficeCapability.verifyDocuments,
  BackOfficeCapability.identityDocuments,
  BackOfficeCapability.verifyIdentity,
  BackOfficeCapability.team,
  BackOfficeCapability.auditAll,
};

const adminMe = StaffMe(
  userId: 'admin-1',
  email: 'admin@realesty.fr',
  role: StaffRole.admin,
  displayName: 'Maxime C.',
  initials: 'MC',
  aal2: true,
  capabilities: adminCapabilities,
);

const expertMe = StaffMe(
  userId: 'expert-1',
  email: 'julien@realesty.fr',
  role: StaffRole.expert,
  displayName: 'Julien M.',
  initials: 'JM',
  aal2: true,
  capabilities: {
    BackOfficeCapability.queueAll,
    BackOfficeCapability.take,
    BackOfficeCapability.startReview,
    BackOfficeCapability.editDraft,
    BackOfficeCapability.certify,
    BackOfficeCapability.attachReport,
    BackOfficeCapability.verifyDocuments,
    BackOfficeCapability.identityDocuments,
    BackOfficeCapability.verifyIdentity,
  },
);

const partnerMe = StaffMe(
  userId: 'partner-1',
  email: 'paul@cabinet.fr',
  role: StaffRole.partnerExpert,
  displayName: 'Paul P.',
  initials: 'PP',
  organisation: 'Cabinet Paul',
  aal2: true,
  capabilities: {
    BackOfficeCapability.startReview,
    BackOfficeCapability.editDraft,
    BackOfficeCapability.submitForApproval,
    BackOfficeCapability.verifyDocuments,
  },
);

MockSessionCubit sessionWith(StaffMe me) {
  final session = MockSessionCubit();
  whenListen(
    session,
    const Stream<SessionState>.empty(),
    initialState: SessionState(status: SessionStatus.ready, me: me),
  );
  when(session.refresh).thenAnswer((_) async {});
  when(session.signOut).thenAnswer((_) async {});
  return session;
}

bool _fontsLoaded = false;

/// Loads the Realesty fonts (for screenshots).
Future<void> loadRealestyFonts() async {
  if (_fontsLoaded) return;
  for (final MapEntry(key: family, value: files)
      in RealestyFonts.files.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

extension PumpBackOffice on WidgetTester {
  /// A desktop surface (1440 × 900 by default).
  void useDesktopSurface([Size size = const Size(1440, 900)]) {
    view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
  }

  /// Pumps [widget] with the theme, localizations and providers.
  Future<void> pumpBo(
    Widget widget, {
    BackOfficeRepository? repository,
    BackOfficeAuthRepository? auth,
    SessionCubit? session,
    Browser? browser,
    BackOfficeConfig config = const BackOfficeConfig(
      authRedirectUrl: 'http://localhost:3000/',
    ),
  }) {
    return pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BackOfficeRepository>.value(
            value: repository ?? MockBackOfficeRepository(),
          ),
          RepositoryProvider<BackOfficeAuthRepository>.value(
            value: auth ?? MockBackOfficeAuthRepository(),
          ),
          RepositoryProvider.value(value: config),
          RepositoryProvider<Browser>.value(value: browser ?? FakeBrowser()),
        ],
        child: BlocProvider<SessionCubit>.value(
          value: session ?? sessionWith(adminMe),
          child: MaterialApp(
            theme: realestyTheme(),
            locale: const Locale('fr'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: widget),
          ),
        ),
      ),
    );
  }
}

Uint8List pdfBytes() => Uint8List.fromList([37, 80, 68, 70]);
