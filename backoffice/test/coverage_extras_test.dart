import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/audit/audit.dart';
import 'package:realesty_backoffice/dossier/dossier.dart';
import 'package:realesty_backoffice/dossier/tabs/documents_tab.dart';
import 'package:realesty_backoffice/dossier/widgets/dossier_labels.dart';
import 'package:realesty_backoffice/l10n/gen/app_localizations_fr.dart';
import 'package:realesty_backoffice/queue/queue.dart';
import 'package:realesty_backoffice/valuation_form/valuation_form.dart';

import 'helpers/fixtures.dart';
import 'helpers/helpers.dart';

void main() {
  final l10n = AppLocalizationsFr();

  test('every label has French text', () {
    for (final code in [
      'required',
      'not_integer',
      'not_number',
      'out_of_range',
      'not_text',
      'too_long',
      'not_bool',
      'invalid_choice',
      'invalid_date',
      'invalid_uuid',
      'range_order',
      'not_list',
      'too_many',
      'not_object',
      'street_number',
      'unknown_field',
    ]) {
      expect(validationMessage(l10n, code), isNotEmpty);
    }
    for (final kind in [
      'titre_propriete',
      'taxe_fonciere',
      'facture_energie',
      'facture_travaux',
      'piece_identite',
      'diagnostics',
      'rapport_spanc',
      'plan',
      'dpe',
      'contrat_entretien',
      'assurance',
      'copropriete',
      'autre',
    ]) {
      expect(documentKindLabel(l10n, kind), isNotEmpty);
    }
    expect(stepLabel(l10n, 'other'), 'other');
    expect(auditActionLabel(l10n, 'other'), 'other');
    expect(const AuditFilters(action: 'certified').props, hasLength(5));
    expect(compactJson(null), '—');
  });

  testWidgets('queue flags: deactivated seller, draft status', (tester) async {
    tester.useDesktopSurface();
    await tester.pumpBo(
      SingleChildScrollView(
        child: Column(
          children: [
            QueueTable(
              rows: [
                DossierSummary(
                  id: 'p1',
                  status: DossierStatus.submitted,
                  submittedAt: DateTime.now(),
                  ownerDeactivated: true,
                ),
              ],
              onOpen: (_) {},
              onTake: (_) {},
              onAssign: (_) {},
            ),
            const DossierStatusChip(DossierStatus.draft),
          ],
        ),
      ),
    );
    expect(find.text('Compte désactivé'), findsOneWidget);
    expect(find.text('Brouillon'), findsOneWidget);
  });

  testWidgets('list editor: list error, cleared cell', (tester) async {
    tester.useDesktopSurface();
    List<JsonMap>? changed;
    await tester.pumpBo(
      SingleChildScrollView(
        child: ListEditor(
          listKey: 'reasons',
          title: 'Raisons',
          columns: const [ListColumn('text', 'Texte')],
          items: const [
            {'text': 'Piscine'},
          ],
          errors: const [ValidationError('reasons', 'too_many')],
          onChanged: (items) => changed = items,
        ),
      ),
    );
    expect(find.text('50 lignes au plus'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), ' ');
    expect(changed, [<String, dynamic>{}]);
  });

  testWidgets('reject dialog: typed reason', (tester) async {
    tester.useDesktopSurface();
    String? reason;
    await tester.pumpBo(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => reason = await showDialog<String>(
            context: context,
            builder: (_) => const RejectDialog(),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Mauvaise année');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Refuser'));
    await tester.pumpAndSettle();
    expect(reason, 'Mauvaise année');
  });

  testWidgets('header: unassigned, lot sold either way; voice without values', (
    tester,
  ) async {
    tester.useDesktopSurface(const Size(1440, 2000));
    final repository = MockBackOfficeRepository();
    final router = MockGoRouter();
    final json = dossierJson();
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async => Dossier.fromJson({
        ...json,
        'assignment': null,
        'lot': {...json['lot'] as Map, 'sale_mode': 'ensemble_ou_separe'},
        'voice_thread': const [
          {
            'step': 'rooms',
            'retained': {'patch': null, 'entity_ops': <dynamic>[]},
          },
        ],
      }),
    );
    await tester.pumpBo(
      InheritedGoRouter(
        goRouter: router,
        child: const DossierPage(propertyId: 'p1', tab: DossierTab.voice),
      ),
      repository: repository,
    );
    await tester.pump();
    expect(find.textContaining('Non attribué'), findsOneWidget);
    expect(find.textContaining('ensemble ou séparément'), findsOneWidget);
    expect(find.textContaining('Retenu'), findsNothing);
  });

  testWidgets('photo that cannot be shown', (tester) async {
    tester.useDesktopSurface(const Size(1440, 2000));
    final repository = MockBackOfficeRepository();
    when(() => repository.getDossier('p1'))
        .thenAnswer((_) async => dossierFixture());
    when(() => repository.signFiles(any(), any())).thenAnswer(
      (_) async => [
        const SignedFile(
          kind: FileKind.photo,
          id: 'ph1',
          url: 'https://example.invalid/ph1.jpg',
        ),
      ],
    );
    await tester.pumpBo(
      InheritedGoRouter(
        goRouter: MockGoRouter(),
        child: const DossierPage(propertyId: 'p1', tab: DossierTab.photos),
      ),
      repository: repository,
    );
    await tester.pump();
    await tester.tap(find.text('Afficher les photos'));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.errorBuilder!(tester.element(find.byType(Image)), Error(), null),
      isA<Center>(),
    );
  });

  testWidgets('conflict without a name; return dialog cancelled', (
    tester,
  ) async {
    tester.useDesktopSurface(const Size(1600, 7000));
    final repository = MockBackOfficeRepository();
    when(() => repository.getDossier('p1')).thenAnswer(
      (_) async => dossierFixture(
        draft: {
          'payload': validPayload,
          'version': 1,
          'status': 'submitted_for_approval',
        },
      ),
    );
    when(
      () => repository.saveDraft(
        any(),
        any(),
        expectedVersion: any(named: 'expectedVersion'),
      ),
    ).thenThrow(const BackOfficeFailure(BackOfficeFailureReason.draftConflict));
    when(repository.listTeam).thenAnswer((_) async => team);
    await tester.pumpBo(
      InheritedGoRouter(
        goRouter: MockGoRouter(),
        child: const DossierPage(propertyId: 'p1', tab: DossierTab.valuation),
      ),
      repository: repository,
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Renvoyer au partenaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    verifyNever(() => repository.returnDraft(any(), any()));
    await tester.enterText(find.byType(EditableText).first, '2000');
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(find.textContaining('Le brouillon a été modifié'), findsWidgets);
  });

  testWidgets('the app releases its router', (tester) async {
    final auth = MockBackOfficeAuthRepository();
    when(() => auth.changes).thenAnswer((_) => const Stream.empty());
    when(() => auth.isSignedIn).thenReturn(false);
    tester.useDesktopSurface();
    await tester.pumpWidget(
      App(
        authRepository: auth,
        repository: MockBackOfficeRepository(),
        config: const BackOfficeConfig(authRedirectUrl: 'http://x/'),
        browser: FakeBrowser(),
        initialLocation: '/dossiers/p1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connexion de l’équipe'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
