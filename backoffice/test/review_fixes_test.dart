import 'dart:typed_data';

import 'package:backoffice_repository/backoffice_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realesty_backoffice/app/app.dart';
import 'package:realesty_backoffice/app/view/config_error.dart';
import 'package:realesty_backoffice/audit/audit.dart';
import 'package:realesty_backoffice/dossier/cubit/dossier_cubit.dart';
import 'package:realesty_backoffice/l10n/gen/app_localizations_fr.dart';
import 'package:realesty_backoffice/valuation_form/valuation_form.dart';

import 'helpers/helpers.dart';

void main() {
  final l10n = AppLocalizationsFr();

  test('PDF checks before the upload', () {
    expect(pdfProblem(l10n, pdfBytes()), isNull);
    expect(
      pdfProblem(l10n, Uint8List.fromList([1, 2, 3, 4, 5])),
      l10n.formReportNotPdf,
    );
    expect(pdfProblem(l10n, Uint8List(2)), l10n.formReportNotPdf);
    expect(
      pdfProblem(l10n, Uint8List(maxReportBytes + 1)),
      l10n.formReportTooLarge,
    );
  });

  test('CSV cells cannot start a formula', () {
    final csv = auditCsv(l10n, [
      AuditEntry(
        id: 1,
        at: DateTime.utc(2026),
        actorRole: 'expert',
        actorName: '=HYPERLINK("x")',
        action: 'document_rejected',
        details: const {'reason': 'x'},
      ),
      AuditEntry(
        id: 2,
        at: DateTime.utc(2026),
        actorRole: 'expert',
        actorName: '@cmd',
        action: '+x',
        propertyId: '-1',
      ),
    ]);
    expect(csv, contains('"\'=HYPERLINK(""x"")"'));
    expect(csv, contains("'@cmd"));
    expect(csv, contains("'+x"));
    expect(csv, contains(";'-1;"));
  });

  test('journal values read the French way', () {
    expect(
      compactJson({'n': 525000, 'x': 1.5}, display: true),
      'n: 525 000, x: 1,50',
    );
    expect(compactJson([1000]), '1000');
  });

  testWidgets('missing configuration screen', (tester) async {
    await tester.pumpWidget(const ConfigErrorApp());
    await tester.pumpAndSettle();
    expect(find.text('Configuration manquante'), findsOneWidget);
  });

  blocTest<ValuationFormCubit, ValuationFormState>(
    'errors show after an edit, all of them after an attempt',
    build: () => ValuationFormCubit(
      repository: MockBackOfficeRepository(),
      propertyId: 'p1',
      draft: null,
      autosaveDelay: const Duration(hours: 1),
    ),
    act: (cubit) {
      expect(cubit.state.visibleErrors, isEmpty);
      cubit.setField('value_eur', 'abc');
      expect(cubit.state.visibleErrors, [
        const ValidationError('value_eur', 'not_integer'),
      ]);
      cubit
        ..setField('comparables', [<String, dynamic>{}])
        ..revealErrors();
    },
    verify: (cubit) {
      expect(cubit.state.visibleErrors, hasLength(cubit.state.errors.length));
      expect(
        cubit.state.visibleErrors.map((e) => e.path),
        contains('comparables[0].street'),
      );
    },
  );

  test('signatory errors from the database have a message', () {
    expect(validationMessage(l10n, 'unknown_signatory'), isNotEmpty);
    expect(
      failureText(
        l10n,
        const BackOfficeFailure(BackOfficeFailureReason.signatoryNotAllowed),
      ),
      l10n.failureSignatory,
    );
    expect(
      failureText(
        l10n,
        const BackOfficeFailure(BackOfficeFailureReason.invalidSignatory),
      ),
      l10n.failureInvalidSignatory,
    );
  });

  testWidgets('a file that is not a PDF is not sent', (tester) async {
    // Covered through CertifiedView in valuation_form_page_test; here the
    // fake browser hands a text file.
    final browser = FakeBrowser()
      ..nextPdf = PickedFile(name: 'x.txt', bytes: Uint8List.fromList([1]));
    final repository = MockBackOfficeRepository();
    tester.useDesktopSurface();
    await tester.pumpBo(
      BlocProvider(
        create: (_) => DossierCubit(repository: repository, propertyId: 'p1'),
        child: const CertifiedView(
          dossier: Dossier(
            id: 'p1',
            role: StaffRole.expert,
            status: DossierStatus.certified,
            property: {'id': 'p1'},
            valuation: {'id': 'v1'},
          ),
        ),
      ),
      repository: repository,
      browser: browser,
      session: sessionWith(expertMe),
    );
    await tester.enterText(find.byType(EditableText), '3');
    await tester.tap(find.text('Choisir le PDF et l’envoyer'));
    await tester.pump();
    expect(find.text('Ce fichier n’est pas un PDF.'), findsOneWidget);
    verifyNever(
      () => repository.uploadReport(any(), any(), pages: any(named: 'pages')),
    );
  });
}
