import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/dossier/dossier.dart';
import 'package:realesty_backoffice/valuation_form/valuation_form.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

Finder field(String label, [int index = 0]) => find
    .descendant(
      of: find.widgetWithText(RealestyTextField, label),
      matching: find.byType(EditableText),
    )
    .at(index);

Finder inList(String key, Finder matching) => find.descendant(
  of: find.byWidgetPredicate((w) => w is ListEditor && w.listKey == key),
  matching: matching,
);

Finder listField(String key, String label, [int index = 0]) => inList(
  key,
  find.descendant(
    of: find.widgetWithText(RealestyTextField, label),
    matching: find.byType(EditableText),
  ),
).at(index);

void main() {
  late MockBackOfficeRepository repository;
  late MockGoRouter router;
  late FakeBrowser browser;
  late Dossier current;

  setUp(() {
    repository = MockBackOfficeRepository();
    router = MockGoRouter();
    browser = FakeBrowser();
    current = dossierFixture();
    when(() => router.go(any())).thenReturn(null);
    when(() => repository.getDossier('p1')).thenAnswer((_) async => current);
    when(
      () => repository.saveDraft(
        any(),
        any(),
        expectedVersion: any(named: 'expectedVersion'),
      ),
    ).thenAnswer(
      (invocation) async =>
          (invocation.namedArguments[#expectedVersion] as int) + 1,
    );
    when(() => repository.certify(any(), version: any(named: 'version')))
        .thenAnswer((_) async => 'v1');
    when(
      () => repository.submitForApproval(any(), version: any(named: 'version')),
    ).thenAnswer((_) async {});
    when(() => repository.returnDraft(any(), any())).thenAnswer((_) async {});
    when(() => repository.listTeam()).thenAnswer(
      (_) async => [
        ...team,
        const StaffMember(
          userId: '11111111-1111-4111-8111-111111111111',
          role: StaffRole.partnerExpert,
          displayName: 'Rita R.',
          initials: 'RR',
          active: true,
        ),
      ],
    );
    when(
      () => repository.uploadReport(any(), any(), pages: any(named: 'pages')),
    ).thenAnswer((_) async {});
    when(() => repository.signFiles(any(), any())).thenAnswer(
      (_) async => [
        const SignedFile(kind: FileKind.report, id: 'v1', url: 'https://pdf'),
      ],
    );
  });

  Future<void> pump(WidgetTester tester, {StaffMe me = adminMe}) async {
    tester.useDesktopSurface(const Size(1600, 7000));
    await tester.pumpBo(
      InheritedGoRouter(
        goRouter: router,
        child: const DossierPage(propertyId: 'p1', tab: DossierTab.valuation),
      ),
      repository: repository,
      browser: browser,
      session: sessionWith(me),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('admin writes, checks and certifies', (tester) async {
    await pump(tester);
    expect(find.text('Pas encore enregistré'), findsOneWidget);
    expect(find.text('3 erreurs à corriger'), findsOneWidget);
    expect(find.textContaining('Tendance IA'), findsOneWidget);

    await tester.tap(find.text('Certifier'));
    await tester.pump();
    expect(
      find.text('Corrigez les erreurs avant de continuer.'),
      findsOneWidget,
    );

    await tester.enterText(field('Valeur certifiée (€)'), '525 000');
    await tester.enterText(field('Bas de fourchette (€)'), '505000');
    await tester.enterText(field('Haut de fourchette (€)'), 'abc');
    await tester.pump();
    expect(find.text('Nombre entier attendu'), findsOneWidget);
    await tester.enterText(field('Haut de fourchette (€)'), '545000');
    await tester.enterText(field('Prix au m² (€, calculé si vide)'), '');
    await tester.pump();
    expect(find.text('Aucune erreur'), findsOneWidget);
    expect(find.text('Modifications en attente…'), findsOneWidget);

    await tester.tap(find.text('Pré-remplir depuis le dossier'));
    await tester.tap(find.text('Importer les ventes DVF'));
    await tester.pump();
    expect(find.text('rue Lucien Cozon'), findsOneWidget);

    await tester.tap(inList('adjustments', find.text('Ajouter une ligne')));
    await tester.pump();
    await tester.enterText(listField('adjustments', 'Libellé'), 'Base');
    await tester.enterText(listField('adjustments', 'Montant (€)'), '100');
    await tester.pump();
    await tester.tap(inList('adjustments', find.text('Ajouter une ligne')));
    await tester.pump();
    await tester.enterText(listField('adjustments', 'Libellé', 1), 'Total');
    await tester.enterText(listField('adjustments', 'Montant (€)', 1), '50');
    await tester.pump();
    expect(find.textContaining('ne correspond pas'), findsNothing);
    await tester.tap(
      inList('adjustments', find.byType(DropdownButtonFormField<String>)).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('ne correspond pas'), findsOneWidget);

    await tester.tap(inList('reasons', find.text('Ajouter une ligne')));
    await tester.pump();
    await tester.tap(inList('reasons', find.text('Ajouter une ligne')));
    await tester.pump();
    await tester.enterText(listField('reasons', 'Texte'), 'Piscine');
    await tester.pump();
    await tester.tap(inList('reasons', find.byType(Checkbox)).first);
    await tester.pump();
    await tester.tap(inList('reasons', find.byTooltip('Monter')).last);
    await tester.pump();
    await tester.tap(
      inList('reasons', find.byTooltip('Supprimer la ligne')).first,
    );
    await tester.pump();
    await tester.tap(
      inList('reasons', find.byTooltip('Supprimer la ligne')).first,
    );
    await tester.pump();

    await tester.enterText(field('Surface (m²)'), '107,5');
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Rita R.').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(find.text('Enregistré · v1'), findsOneWidget);

    await tester.tap(find.text('Certifier'));
    await tester.pumpAndSettle();
    expect(find.text('Certifier l’avis de valeur'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    current = dossierFixture(
      status: 'certified',
      valuation: {'id': 'v1', 'value_eur': 525000},
    );
    await tester.tap(find.text('Certifier'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Certifier'));
    await tester.pumpAndSettle();
    verify(() => repository.certify('p1', version: 1)).called(1);
    expect(find.text('Avis de valeur certifié'), findsOneWidget);
    final saved =
        verify(
              () =>
                  repository.saveDraft('p1', captureAny(), expectedVersion: 0),
            ).captured.last
            as JsonMap;
    expect(saved['expert_user_id'], '11111111-1111-4111-8111-111111111111');
    expect(saved['value_eur'], 525000);
  });

  testWidgets('partner submits; then the form is read-only', (tester) async {
    current = dossierFixture(
      role: 'partner_expert',
      partner: true,
      draft: {
        'payload': validPayload,
        'version': 2,
        'approval_note': 'Revoir les comparables',
      },
    );
    await pump(tester, me: partnerMe);
    expect(find.textContaining('Revoir les comparables'), findsOneWidget);
    expect(find.text('Certifier'), findsNothing);
    expect(find.text('Rapport saisi pour'), findsNothing);
    await tester.tap(find.text('Soumettre pour validation'));
    await tester.pump();
    verify(() => repository.submitForApproval('p1', version: 2)).called(1);
    expect(find.textContaining('va le relire'), findsOneWidget);
    expect(find.text('Soumettre pour validation'), findsNothing);
  });

  testWidgets('partner: errors block the submission', (tester) async {
    current = dossierFixture(role: 'partner_expert', partner: true);
    await pump(tester, me: partnerMe);
    await tester.tap(find.text('Soumettre pour validation'));
    await tester.pump();
    expect(
      find.text('Corrigez les erreurs avant de continuer.'),
      findsOneWidget,
    );
  });

  testWidgets('expert sends a submitted draft back', (tester) async {
    current = dossierFixture(
      role: 'expert',
      draft: {
        'payload': validPayload,
        'version': 4,
        'status': 'submitted_for_approval',
        'submitted_by_name': 'Paul P.',
      },
    );
    await pump(tester, me: expertMe);
    expect(find.text('Soumis pour validation par Paul P.'), findsOneWidget);
    await tester.tap(find.text('Renvoyer au partenaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Renvoyer au partenaire'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.returnDraft(any(), any()));
    await tester.tap(find.text('Renvoyer au partenaire'));
    await tester.pumpAndSettle();
    await tester.enterText(
      field('Commentaire pour l’auteur'),
      'Ajouter les comparables',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Renvoyer au partenaire'));
    await tester.pumpAndSettle();
    verify(() => repository.returnDraft('p1', 'Ajouter les comparables'))
        .called(1);
    expect(
      find.text('Renvoyé avec ce commentaire : Ajouter les comparables'),
      findsOneWidget,
    );
  });

  testWidgets('a conflict asks to reload', (tester) async {
    when(
      () => repository.saveDraft(
        any(),
        any(),
        expectedVersion: any(named: 'expectedVersion'),
      ),
    ).thenThrow(
      const BackOfficeFailure(
        BackOfficeFailureReason.draftConflict,
        details: 'Paul P.',
      ),
    );
    await pump(tester, me: expertMe);
    await tester.enterText(field('Valeur certifiée (€)'), '1000');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(
      find.textContaining('Modifié entre-temps par Paul P.'),
      findsOneWidget,
    );
    current = dossierFixture(draft: {'payload': validPayload, 'version': 9});
    await tester.tap(find.text('Recharger'));
    await tester.pump();
    expect(find.text('Enregistré · v9'), findsOneWidget);
  });

  testWidgets('certified: the PDF', (tester) async {
    current = dossierFixture(
      status: 'certified',
      valuation: {
        'id': 'v1',
        'value_eur': 525000,
        'low_eur': 505000,
        'high_eur': 545000,
        'expert_display_name': 'Julien M.',
        'certified_at': '2026-10-03T10:00:00Z',
        'report_storage_path': 'o/p1/avis.pdf',
        'report_pages': 11,
      },
    );
    await pump(tester, me: expertMe);
    expect(find.text('PDF joint · 11 pages'), findsOneWidget);
    await tester.tap(find.text('Ouvrir le PDF'));
    await tester.pump();
    expect(browser.opened.single, 'https://pdf');

    await tester.tap(find.text('Choisir le PDF et l’envoyer'));
    await tester.pump();
    expect(find.textContaining('nombre de pages'), findsOneWidget);
    await tester.enterText(field('Nombre de pages'), '12');
    await tester.tap(find.text('Choisir le PDF et l’envoyer'));
    await tester.pump();
    verifyNever(
      () => repository.uploadReport(any(), any(), pages: any(named: 'pages')),
    );
    browser.nextPdf = PickedFile(name: 'avis.pdf', bytes: pdfBytes());
    await tester.tap(find.text('Choisir le PDF et l’envoyer'));
    await tester.pump();
    await tester.pump();
    verify(() => repository.uploadReport('p1', any(), pages: 12)).called(1);
  });

  testWidgets('certified, partner: no upload', (tester) async {
    current = dossierFixture(
      role: 'partner_expert',
      partner: true,
      status: 'certified',
      valuation: {'id': 'v1'},
    );
    await pump(tester, me: partnerMe);
    expect(find.text('Choisir le PDF et l’envoyer'), findsNothing);
    expect(find.text('Ouvrir le PDF'), findsNothing);
  });

  testWidgets('a bad signatory shows once certification is tried', (
    tester,
  ) async {
    current = dossierFixture(
      role: 'expert',
      draft: {
        'payload': {...validPayload, 'expert_user_id': 'x'},
        'version': 1,
      },
    );
    await pump(tester, me: expertMe);
    expect(find.text('Signataire\u00a0: par défaut'), findsOneWidget);
    expect(find.text('Identifiant invalide'), findsNothing);
    await tester.tap(find.text('Certifier'));
    await tester.pump();
    expect(find.text('Identifiant invalide'), findsOneWidget);
  });
}
