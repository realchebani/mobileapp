import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/queue/queue.dart';
import 'package:realesty_backoffice/queue/widgets/assign_dialog.dart';
import 'package:realesty_ui/realesty_ui.dart';

import '../helpers/fixtures.dart';
import '../helpers/helpers.dart';

void main() {
  late MockBackOfficeRepository repository;

  void stubList(Future<List<DossierSummary>> Function() rows) => when(
    () => repository.listDossiers(
      statuses: any(named: 'statuses'),
      scope: any(named: 'scope'),
      search: any(named: 'search'),
      limit: any(named: 'limit'),
      offset: any(named: 'offset'),
    ),
  ).thenAnswer((_) => rows());

  setUp(() {
    repository = MockBackOfficeRepository();
    stubList(
      () async => [
        summary(
          lot: const LotRef(id: 'l1', name: 'Maison + terrain'),
          draftVersion: 3,
        ),
        summary(
          id: 'p2',
          status: DossierStatus.inReview,
          submitted: DateTime.now().subtract(const Duration(hours: 5)),
          assignedTo: const StaffRef(
            userId: 'expert-1',
            displayName: 'Julien M.',
          ),
          draftStatus: ValuationDraftStatus.submittedForApproval,
        ),
        const DossierSummary(id: 'p3', status: DossierStatus.certified),
      ],
    );
    when(() => repository.startReview(any())).thenAnswer((_) async {});
    when(() => repository.assign(any(), any(), note: any(named: 'note')))
        .thenAnswer((_) async {});
    when(() => repository.unassign(any())).thenAnswer((_) async {});
    when(() => repository.listTeam()).thenAnswer((_) async => team);
  });

  testWidgets('admin: the table, its flags and actions', (tester) async {
    tester.useDesktopSurface();
    await tester.pumpBo(const QueuePage(), repository: repository);
    await tester.pump();
    expect(find.text('Maison · 115 m²'), findsNWidgets(2));
    expect(find.textContaining('Plus de 48'), findsOneWidget);
    expect(find.textContaining('il y a 5'), findsOneWidget);
    expect(find.text('Lot : Maison + terrain'), findsOneWidget);
    expect(find.text('2 documents à vérifier'), findsNWidgets(2));
    expect(find.text('Brouillon v3'), findsOneWidget);
    expect(find.text('À valider'), findsOneWidget);
    expect(find.text('Julien M.'), findsOneWidget);
    expect(find.text('Aucune photo'), findsOneWidget);
    expect(find.text('Toute l’équipe'), findsOneWidget);

    await tester.tap(find.text('Prendre en charge'));
    await tester.pump();
    verify(() => repository.startReview('p1')).called(1);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.text('Certifiés'));
    await tester.pump();
    await tester.tap(find.text('Non attribués'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Lyon');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    verify(
      () => repository.listDossiers(
        statuses: [DossierStatus.certified],
        scope: DossierScope.unassigned,
        search: 'Lyon',
      ),
    ).called(1);
  });

  testWidgets('admin: assign, change and remove', (tester) async {
    tester.useDesktopSurface();
    await tester.pumpBo(const QueuePage(), repository: repository);
    await tester.pump();
    await tester.tap(find.text('Attribuer').first);
    await tester.pumpAndSettle();
    expect(find.text('Attribuer le dossier'), findsOneWidget);
    expect(find.text('Ancien'), findsNothing);
    await tester.tap(find.text('Paul P.'));
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(AssignDialog),
        matching: find.byType(EditableText),
      ),
      'Urgent',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Attribuer').last);
    await tester.pumpAndSettle();
    verify(() => repository.assign('p1', 'partner-1', note: 'Urgent'))
        .called(1);
    expect(find.text('Dossier attribué à Paul P..'), findsOneWidget);

    await tester.tap(find.text('Attribuer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retirer l’attribution'));
    await tester.pumpAndSettle();
    verify(() => repository.unassign('p2')).called(1);

    await tester.tap(find.text('Attribuer').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    verifyNever(
      () => repository.assign('p2', any(), note: any(named: 'note')),
    );
  });

  testWidgets('opens a dossier', (tester) async {
    tester.useDesktopSurface();
    final router = MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
    await tester.pumpBo(
      InheritedGoRouter(goRouter: router, child: const QueuePage()),
      repository: repository,
    );
    await tester.pump();
    await tester.tap(find.text('Ouvrir').first);
    verify(() => router.go('/dossiers/p1')).called(1);
  });

  testWidgets('partner: no scope, no assignment; empty and errors', (
    tester,
  ) async {
    tester.useDesktopSurface();
    stubList(() async => []);
    await tester.pumpBo(
      const QueuePage(),
      repository: repository,
      session: sessionWith(partnerMe),
    );
    await tester.pump();
    expect(find.text('Toute l’équipe'), findsNothing);
    expect(find.text('Aucun dossier'), findsOneWidget);

    stubList(() async => throw Exception('x'));
    await tester.tap(find.text('Tous'));
    await tester.pump();
    expect(find.text('La file n’a pas pu être chargée.'), findsOneWidget);
    stubList(() async => List.generate(100, (i) => summary(id: 'p$i')));
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    expect(find.text('Attribuer'), findsNothing);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Afficher plus'),
      find.byType(ListView).first,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    stubList(() async => [summary(id: 'last')]);
    tester
        .widget<RealestyButton>(
          find.widgetWithText(RealestyButton, 'Afficher plus'),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    verify(
      () => repository.listDossiers(
        statuses: any(named: 'statuses'),
        scope: any(named: 'scope'),
        search: any(named: 'search'),
        limit: any(named: 'limit'),
        offset: 100,
      ),
    ).called(1);
    expect(find.text('Afficher plus'), findsNothing);
  });

  testWidgets('a busy row shows a spinner', (tester) async {
    tester.useDesktopSurface();
    await tester.pumpBo(
      SingleChildScrollView(
        child: QueueTable(
          rows: [summary()],
          busyId: 'p1',
          onOpen: (_) {},
          onTake: (_) {},
          onAssign: (_) {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
