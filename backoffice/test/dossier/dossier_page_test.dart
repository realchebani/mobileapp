import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/dossier/dossier.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

void main() {
  late MockBackOfficeRepository repository;
  late MockGoRouter router;
  late FakeBrowser browser;

  setUp(() {
    repository = MockBackOfficeRepository();
    router = MockGoRouter();
    browser = FakeBrowser();
    when(() => router.go(any())).thenReturn(null);
    when(() => repository.getDossier('p1'))
        .thenAnswer((_) async => dossierFixture());
    when(() => repository.startReview(any())).thenAnswer((_) async {});
    when(() => repository.verifyDocument(any())).thenAnswer((_) async {});
    when(() => repository.rejectDocument(any(), any()))
        .thenAnswer((_) async {});
    when(() => repository.verifyIdentity(any())).thenAnswer((_) async {});
    when(() => repository.signFiles(any(), any())).thenAnswer(
      (invocation) async => [
        for (final file
            in invocation.positionalArguments[1] as List<FileRequest>)
          SignedFile(kind: file.kind, id: file.id, url: 'https://s/${file.id}'),
      ],
    );
    when(() => repository.audit(propertyId: any(named: 'propertyId')))
        .thenAnswer(
          (_) async => [
            AuditEntry(
              id: 1,
              at: DateTime(2026, 10, 3, 10),
              actorRole: 'expert',
              actorName: 'Julien M.',
              action: 'dossier_opened',
            ),
            AuditEntry(
              id: 2,
              at: DateTime(2026, 10, 3, 11),
              actorRole: 'sql_editor',
              action: 'certified',
              details: const {'value_eur': 525000},
            ),
          ],
        );
  });

  Future<void> pump(
    WidgetTester tester,
    DossierTab tab, {
    StaffMe me = adminMe,
  }) async {
    tester.useDesktopSurface(const Size(1440, 2400));
    await tester.pumpBo(
      InheritedGoRouter(
        goRouter: router,
        child: DossierPage(propertyId: 'p1', tab: tab),
      ),
      repository: repository,
      browser: browser,
      session: sessionWith(me),
    );
    await tester.pump();
  }

  testWidgets('synthesis: owners, answers, rooms, market, lot', (tester) async {
    await pump(tester, DossierTab.synthesis);
    expect(find.text('Maison · 115 m² · Chaponost'), findsOneWidget);
    expect(find.textContaining('Attribué à Julien M.'), findsOneWidget);
    expect(find.textContaining('a demandé la suppression'), findsOneWidget);
    expect(find.text('Identité non vérifiée'), findsOneWidget);
    expect(find.textContaining('Identité vérifiée le'), findsOneWidget);
    expect(find.textContaining('sophie@example.test'), findsWidgets);
    expect(find.text('Section AB n° 12 · 540 m²'), findsOneWidget);
    expect(find.text('À vérifier'), findsOneWidget);
    expect(find.text('Non confirmé'), findsOneWidget);
    expect(find.text('Dit à une autre étape'), findsOneWidget);
    expect(find.text('Source invalide'), findsOneWidget);
    expect(find.text('Non tracé'), findsOneWidget);
    expect(find.text('Lumineux'), findsOneWidget);
    expect(find.text('Agence du Centre'), findsOneWidget);
    expect(find.text('Toiture refaite en 2016'), findsOneWidget);
    expect(find.text('72 %'), findsOneWidget);
    expect(find.text('Onze ventes récentes.'), findsOneWidget);
    expect(find.textContaining('1/3 certifié'), findsOneWidget);

    await tester.tap(find.text('Voir sur Géoportail'));
    expect(browser.opened.single, contains('c=4.74,45.7'));
    await tester.tap(find.text('Marquer l’identité comme vérifiée'));
    await tester.pump();
    verify(() => repository.verifyIdentity('o1')).called(1);
    await tester.tap(find.textContaining('Terrain'));
    verify(() => router.go('/dossiers/p9')).called(1);
    await tester.tap(find.text('Prendre en charge'));
    await tester.pump();
    verify(() => repository.startReview('p1')).called(1);
    await tester.tap(find.text('Rédiger l’avis de valeur'));
    verify(() => router.go('/dossiers/p1/avis')).called(1);
    await tester.tap(find.text('Photos'));
    verify(() => router.go('/dossiers/p1/photos')).called(1);
    await tester.tap(find.text('Dossiers').first);
    verify(() => router.go('/dossiers')).called(1);
  });

  testWidgets('synthesis of a certified dossier without market', (
    tester,
  ) async {
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async => Dossier.fromJson({
        ...dossierJson(
          status: 'certified',
          valuation: {
            'value_eur': 525000,
            'low_eur': 505000,
            'high_eur': 545000,
            'expert_display_name': 'Julien M.',
            'certified_at': '2026-10-03T10:00:00Z',
          },
        ),
        'market': null,
        'lot': null,
        'fill_sheet': const <dynamic>[],
      }),
    );
    await pump(tester, DossierTab.synthesis);
    expect(
      find.text('Pas d’estimation automatique pour ce dossier.'),
      findsOneWidget,
    );
    expect(find.text('Aucune réponse enregistrée.'), findsOneWidget);
    expect(find.textContaining('525 000 € (de'), findsOneWidget);
    expect(find.text('Rédiger l’avis de valeur'), findsNothing);
  });

  testWidgets('photos: signed, opened, flagged', (tester) async {
    await pump(tester, DossierTab.photos);
    expect(find.text('Pièce principale sans photo'), findsOneWidget);
    expect(find.text('Personne visible'), findsOneWidget);
    expect(find.textContaining('fissure au plafond'), findsOneWidget);
    expect(find.text('Contrôles : dark'), findsOneWidget);
    await tester.tap(find.text('Afficher les photos'));
    await tester.pump();
    expect(find.text('Recharger les photos'), findsOneWidget);
    await tester.tap(find.byType(InkWell).at(10), warnIfMissed: false);
    await tester.tap(find.bySemanticsLabel('Ouvrir en grand').first);
    expect(browser.opened, contains('https://s/ph1'));
  });

  testWidgets('photos: none', (tester) async {
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async => Dossier.fromJson({
        ...dossierJson(),
        'photos': const <dynamic>[],
        'rooms': const <dynamic>[],
      }),
    );
    await pump(tester, DossierTab.photos);
    expect(find.text('Aucune photo pour ce dossier.'), findsOneWidget);
  });

  testWidgets('documents: open, verify, refuse', (tester) async {
    await pump(tester, DossierTab.documents);
    expect(find.text('Pièces d’identité'), findsOneWidget);
    expect(find.text('Ajouté après l’envoi'), findsOneWidget);
    expect(find.text('Remplacé'), findsOneWidget);
    expect(find.text('Refusé : Illisible'), findsOneWidget);
    expect(find.textContaining('Vérifié le'), findsOneWidget);

    await tester.tap(find.text('Ouvrir').first);
    await tester.pump();
    expect(browser.opened.single, 'https://s/d1');

    await tester.tap(find.text('Vérifier').first);
    await tester.pump();
    verify(() => repository.verifyDocument('d1')).called(1);

    await tester.tap(find.text('Refuser').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refuser').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Document expiré'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Refuser').last);
    await tester.pumpAndSettle();
    verify(() => repository.rejectDocument('d1', 'Document expiré')).called(1);
  });

  testWidgets('documents: none', (tester) async {
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async =>
          Dossier.fromJson({...dossierJson(), 'documents': const <dynamic>[]}),
    );
    await pump(tester, DossierTab.documents);
    expect(find.text('Aucun document.'), findsOneWidget);
  });

  testWidgets('voice: fill sheet and thread', (tester) async {
    await pump(tester, DossierTab.voice);
    expect(find.text('« construite en 1998 »'), findsOneWidget);
    expect(find.text('Tour annulé par le vendeur'), findsOneWidget);
    expect(find.textContaining('Retenu'), findsOneWidget);
    expect(find.textContaining('Écarté'), findsOneWidget);
    expect(find.textContaining('Pour une autre étape'), findsOneWidget);
    expect(find.text('timeout'), findsOneWidget);
  });

  testWidgets('voice: none', (tester) async {
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async => Dossier.fromJson({
        ...dossierJson(),
        'voice_thread': const <dynamic>[],
        'fill_sheet': const <dynamic>[],
      }),
    );
    await pump(tester, DossierTab.voice);
    expect(find.text('Aucune conversation vocale.'), findsOneWidget);
  });

  testWidgets('journal of the dossier', (tester) async {
    await pump(tester, DossierTab.journal);
    await tester.pump();
    expect(find.textContaining('Dossier ouvert · Julien M.'), findsOneWidget);
    expect(find.textContaining('Certifié · Éditeur SQL'), findsOneWidget);
    expect(find.text('value_eur: 525\u00a0000'), findsOneWidget);
  });

  testWidgets('journal: empty', (tester) async {
    when(() => repository.audit(propertyId: any(named: 'propertyId')))
        .thenAnswer((_) async => []);
    await pump(tester, DossierTab.journal);
    await tester.pump();
    expect(find.text('Aucune action enregistrée.'), findsOneWidget);
  });

  testWidgets('partner: masked owners, no identity section', (tester) async {
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async => dossierFixture(role: 'partner_expert', partner: true),
    );
    await pump(tester, DossierTab.documents, me: partnerMe);
    expect(find.textContaining('Accès expert partenaire'), findsOneWidget);
    expect(find.text('Pièces d’identité'), findsNothing);
    await tester.tap(find.text('Synthèse'));
    verify(() => router.go('/dossiers/p1/synthese')).called(1);
  });

  testWidgets('a dossier that cannot be loaded', (tester) async {
    when(() => repository.getDossier('p1')).thenThrow(
      const BackOfficeFailure(BackOfficeFailureReason.dossierNotFound),
    );
    await pump(tester, DossierTab.synthesis, me: expertMe);
    await tester.pump();
    expect(find.text('Le dossier n’a pas pu être chargé.'), findsOneWidget);
    await tester.tap(find.text('Dossiers'));
    verify(() => router.go('/dossiers')).called(1);
  });

  test('tabs from their URL segment', () {
    expect(DossierTab.fromSegment('voix'), DossierTab.voice);
    expect(DossierTab.fromSegment('nope'), DossierTab.synthesis);
    expect(DossierTab.fromSegment(null), DossierTab.synthesis);
  });
}
