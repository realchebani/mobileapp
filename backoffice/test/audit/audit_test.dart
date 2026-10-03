import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/audit/audit.dart';
import 'package:realesty_backoffice/l10n/gen/app_localizations_fr.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

Finder field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(EditableText),
);

final entries = [
  AuditEntry(
    id: 2,
    at: DateTime.utc(2026, 10, 3, 9),
    actorUserId: 'expert-1',
    actorRole: 'expert',
    actorName: 'Julien M.',
    action: 'certified',
    propertyId: 'p1',
    targetType: 'valuation',
    targetId: 'v1',
    details: const {'value_eur': 525000},
  ),
  AuditEntry(
    id: 1,
    at: DateTime.utc(2026, 10, 3, 8),
    actorRole: 'sql_editor',
    action: 'document_rejected',
    details: const {'reason': 'Page 2; "illisible"'},
  ),
];

void main() {
  late MockBackOfficeRepository repository;

  setUp(() {
    repository = MockBackOfficeRepository();
    when(
      () => repository.audit(
        propertyId: any(named: 'propertyId'),
        actorUserId: any(named: 'actorUserId'),
        action: any(named: 'action'),
        since: any(named: 'since'),
        until: any(named: 'until'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => entries);
    when(() => repository.listTeam()).thenAnswer((_) async => team);
  });

  test('CSV with semicolons and quotes', () {
    final csv = auditCsv(AppLocalizationsFr(), entries);
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('Date;Personne;role;Action'));
    expect(
      lines[1],
      [
        '2026-10-03T09:00:00.000Z',
        'Julien M.',
        'expert',
        'Certifié',
        'certified',
        'p1',
        'valuation:v1',
        'value_eur: 525000',
      ].join(';'),
    );
    expect(lines[2], contains('"reason: Page 2; ""illisible"""'));
    expect(lines[2], contains('Éditeur SQL'));
  });

  testWidgets('filters, exports', (tester) async {
    tester.useDesktopSurface(const Size(1600, 1200));
    final browser = FakeBrowser();
    await tester.pumpBo(
      const AuditPage(),
      repository: repository,
      browser: browser,
    );
    await tester.pump();
    expect(find.text('Certifié · Julien M.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paul P.').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Certifié').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Dossier (identifiant)'), 'p1');
    await tester.enterText(field('Du (AAAA-MM-JJ)'), '2026-02-30');
    await tester.tap(find.text('Filtrer'));
    await tester.pump();
    expect(find.text('Date invalide (AAAA-MM-JJ).'), findsOneWidget);
    await tester.enterText(field('Du (AAAA-MM-JJ)'), 'x');
    await tester.tap(find.text('Filtrer'));
    await tester.pump();
    await tester.enterText(field('Du (AAAA-MM-JJ)'), '2026-10-01');
    await tester.enterText(field('Au (AAAA-MM-JJ, inclus)'), '2026-10-03');
    await tester.tap(find.text('Filtrer'));
    await tester.pump();
    verify(
      () => repository.audit(
        propertyId: 'p1',
        actorUserId: 'partner-1',
        action: 'certified',
        since: DateTime(2026, 10),
        until: DateTime(2026, 10, 4),
        limit: AuditCubit.limit,
      ),
    ).called(1);

    await tester.tap(find.text('Exporter en CSV'));
    await tester.pump();
    expect(browser.saved.single.$1, startsWith('journal-realesty-'));
    expect(find.text('2 lignes exportées'), findsOneWidget);
  });

  testWidgets('empty and failing journal', (tester) async {
    tester.useDesktopSurface(const Size(1600, 1200));
    when(
      () => repository.audit(
        propertyId: any(named: 'propertyId'),
        actorUserId: any(named: 'actorUserId'),
        action: any(named: 'action'),
        since: any(named: 'since'),
        until: any(named: 'until'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => []);
    await tester.pumpBo(const AuditPage(), repository: repository);
    await tester.pump();
    expect(find.text('Aucune action pour ces filtres.'), findsOneWidget);
    when(
      () => repository.audit(
        propertyId: any(named: 'propertyId'),
        actorUserId: any(named: 'actorUserId'),
        action: any(named: 'action'),
        since: any(named: 'since'),
        until: any(named: 'until'),
        limit: any(named: 'limit'),
      ),
    ).thenThrow(Exception('x'));
    await tester.tap(find.text('Filtrer'));
    await tester.pump();
    expect(find.text('Le journal n’a pas pu être chargé.'), findsOneWidget);
  });
}
