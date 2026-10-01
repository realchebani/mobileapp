import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/cubit/documents_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/cubit/document_scan_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/document_scan_page.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

class _MockScanPdfBuilder extends Mock implements ScanPdfBuilder;

const _nbsp = ' ';

/// A 1×1 transparent PNG.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

XFile _file(String name) => XFile.fromData(_png, path: name);

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is RealestyButton && w.label == label);

void main() {
  late _MockDocumentPicker picker;
  late _MockScanPdfBuilder pdfBuilder;
  late List<PickedDocument?> results;

  setUp(() {
    picker = _MockDocumentPicker();
    pdfBuilder = _MockScanPdfBuilder();
    results = [];
    when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
        .thenAnswer((_) async => [_file('a.jpg'), _file('b.jpg')]);
    when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
        .thenAnswer((_) async => Uint8List.fromList([1, 2]));
  });

  /// A page opening the scan of a title deed.
  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    usePhoneSurface();
    await tester.pumpApp(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DocumentPicker>.value(value: picker),
          RepositoryProvider<ScanPdfBuilder>.value(value: pdfBuilder),
        ],
        child: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => results.add(
                await showDocumentScan(context, kind: DocumentKind.titleDeed),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  }

  DocumentScanState stateOf(WidgetTester tester) => tester
      .element(find.byType(DocumentScanView))
      .read<DocumentScanCubit>()
      .state;

  group(DocumentScanPage, () {
    testWidgets('scans at once and shows the pages', (tester) async {
      await open(tester);

      verify(() => picker.scanPages(maxPages: DocumentScanCubit.maxPages))
          .called(1);
      expect(find.text('Scan multipage'), findsOneWidget);
      expect(find.text('Titre de propriété'), findsOneWidget);
      expect(find.text('2 pages'), findsOneWidget);
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(
        find.text(
          'Maintenez une page appuyée pour la déplacer. Les pages forment un '
          'seul PDF.',
        ),
        findsOneWidget,
      );
      final delete = tester.getSize(
        find.bySemanticsLabel('Supprimer la page 1'),
      );
      expect(delete.height, greaterThanOrEqualTo(44));
    });

    testWidgets('adds, deletes and moves pages', (tester) async {
      await open(tester);
      final first = stateOf(tester).pages.first;

      await tester.tap(_button('Ajouter une page'));
      await tester.pumpAndSettle();
      verify(() => picker.scanPages(maxPages: DocumentScanCubit.maxPages - 2))
          .called(1);
      expect(find.text('4 pages'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Supprimer la page 4'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Supprimer la page 3'));
      await tester.pump();
      expect(find.text('2 pages'), findsOneWidget);

      // Long press, then drag the first page below the second.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Page 1')),
      );
      await tester.pump(kLongPressTimeout + kPressTimeout);
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(stateOf(tester).pages.last, first);

      await tester.tap(find.bySemanticsLabel('Supprimer la page 1'));
      await tester.pump();
      expect(find.text('1 page'), findsOneWidget);
      expect(
        find.text(
          'Ajoutez les autres pages du document, puis touchez '
          '«${_nbsp}Terminer$_nbsp».',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Terminer" returns the PDF of the pages', (tester) async {
      final pdf = Completer<Uint8List>();
      when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
          .thenAnswer((_) => pdf.future);
      await open(tester);

      await tester.tap(_button('Terminer'));
      await tester.pump();
      expect(find.text('Préparation du PDF (2 pages)…'), findsOneWidget);
      final finish = tester.widget<RealestyButton>(_button('Terminer'));
      expect(finish.isLoading, isTrue);
      expect(finish.loadingSemanticLabel, 'Préparation du PDF');
      expect(
        tester.widget<RealestyButton>(_button('Ajouter une page')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<RealestyIconButton>(find.byType(RealestyIconButton).first)
            .onPressed,
        isNull,
      );

      pdf.complete(Uint8List.fromList([4, 2]));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentScanView), findsNothing);
      final result = results.single!;
      expect(result.mimeType, 'application/pdf');
      expect(result.bytes, [4, 2]);
      expect(
        result.fileName,
        matches(
          RegExp(
            r'^Titre de propriété - scan du \d{4}-\d\d-\d\d \d\dh\d\d\.pdf$',
          ),
        ),
      );
      verify(
        () => pdfBuilder.build([
          _png,
          _png,
        ], maxBytes: DocumentsCubit.maxFileBytes),
      ).called(1);
    });

    testWidgets('tells when the PDF is too large', (tester) async {
      when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
          .thenThrow(const ScanTooLarge());
      await open(tester);

      await tester.tap(_button('Terminer'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Ce document dépasse 20${_nbsp}Mo, même compressé. Retirez des '
          'pages ou envoyez-le en plusieurs fois.',
        ),
        findsOneWidget,
      );
      expect(find.byType(DocumentScanView), findsOneWidget);
    });

    testWidgets('tells when the PDF cannot be made', (tester) async {
      when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
          .thenThrow(const FormatException('page'));
      await open(tester);

      await tester.tap(_button('Terminer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Impossible de préparer le PDF. Réessayez.'),
        findsOneWidget,
      );
      expect(
        tester.widget<RealestyButton>(_button('Terminer')).onPressed,
        isNotNull,
      );
    });

    testWidgets('closes when the first scan is cancelled', (tester) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
          .thenAnswer((_) async => null);
      await open(tester);

      expect(find.byType(DocumentScanView), findsNothing);
      expect(results, [null]);
    });

    testWidgets('shows the scanner being open', (tester) async {
      final pages = Completer<List<XFile>?>();
      when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
          .thenAnswer((_) => pages.future);
      await open(tester, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Aucune page'), findsOneWidget);
      expect(
        tester.widget<RealestyButton>(_button('Terminer')).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<RealestyIconButton>(find.byType(RealestyIconButton))
            .onPressed,
        isNull,
      );

      pages.complete([_file('a.jpg')]);
      await tester.pumpAndSettle();
      expect(find.text('1 page'), findsOneWidget);
    });

    testWidgets('stays open when the first scan fails', (tester) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
          .thenThrow(Exception('boom'));
      await open(tester);

      expect(find.text('Le scan a échoué. Réessayez.'), findsOneWidget);
      expect(
        find.text(
          'Aucune page pour l’instant. Scannez votre document page par page.',
        ),
        findsOneWidget,
      );

      // Nothing to lose: closes at once.
      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentScanView), findsNothing);
      expect(results, [null]);
    });

    testWidgets('tells when the camera access was refused', (tester) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
          .thenThrow(const DocumentAccessDenied('denied'));
      await open(tester);

      expect(
        find.text(
          'Accès refusé. Autorisez l’accès à l’appareil photo ou aux photos '
          'dans les Réglages.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('asks before dropping the scanned pages', (tester) async {
      await open(tester);

      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Abandonner ce scan$_nbsp?'), findsOneWidget);
      expect(find.text('Les 2 pages scannées seront perdues.'), findsOneWidget);
      await tester.tap(_button('Continuer le scan'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentScanView), findsOneWidget);

      // Dismissed: the scan goes on.
      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentScanView), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Fermer'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Abandonner'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentScanView), findsNothing);
      expect(results, [null]);
    });

    testWidgets('stops at ${DocumentScanCubit.maxPages} pages', (tester) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages'))).thenAnswer(
        (_) async => [
          for (var i = 0; i < DocumentScanCubit.maxPages; i++) _file('$i.jpg'),
        ],
      );
      await open(tester);

      expect(find.text('30 pages maximum par document'), findsOneWidget);
      // Not truncated: exactly the limit.
      expect(find.textContaining('Limite de'), findsNothing);
      expect(
        tester.widget<RealestyButton>(_button('Ajouter une page')).onPressed,
        isNull,
      );
    });

    testWidgets('tells when pages beyond the limit were dropped', (
      tester,
    ) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages'))).thenAnswer(
        (_) async => [
          for (var i = 0; i <= DocumentScanCubit.maxPages; i++) _file('$i.jpg'),
        ],
      );
      await open(tester);

      expect(
        find.text(
          'Limite de 30 pages atteinte$_nbsp: les pages en trop n’ont pas '
          'été ajoutées.',
        ),
        findsOneWidget,
      );
      expect(find.text('30 pages'), findsOneWidget);
    });

    testWidgets('shows an icon for a page it cannot preview', (tester) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages'))).thenAnswer(
        (_) async => [XFile.fromData(Uint8List(8), path: 'broken.heic')],
      );
      await open(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is RealestyIcon && w.icon == RealestyIcons.file,
        ),
        findsOneWidget,
      );
    });

    testWidgets('names the PDF after the kind and the date', (tester) async {
      await tester.pumpApp(const SizedBox());
      final l10n = tester.element(find.byType(SizedBox)).l10n;

      expect(
        DocumentScanView.fileName(
          l10n,
          DocumentKind.identityDocument,
          DateTime(2026, 1, 2, 3, 4),
        ),
        'Pièce d’identité - scan du 2026-01-02 03h04.pdf',
      );
    });
  });
}
