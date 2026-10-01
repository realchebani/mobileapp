import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/scan/document_scan_page.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_files_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/transparency_score_card.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

class _MockScanPdfBuilder extends Mock implements ScanPdfBuilder;

const _nbsp = '\u00a0';

PropertyDocument _document(
  String id,
  DocumentKind kind, {
  DocumentStatus status = DocumentStatus.received,
  String? fileName,
}) => PropertyDocument(
  id: id,
  propertyId: 'property-id',
  kind: kind,
  storagePath: 'user-id/property-id/$id',
  fileName: fileName ?? '$id.pdf',
  sizeBytes: 1258291,
  status: status,
  uploadedAt: DateTime(2026, 9, 24, 18, 42),
);

final PropertyDocument _titleDeed = _document(
  'd1',
  DocumentKind.titleDeed,
  status: DocumentStatus.analyzed,
  fileName: 'titre.pdf',
);

/// The dossier of the mockup: on the sewer, V1–V6 done, four kinds
/// provided.
final _mockupState = SellerTunnelState(
  status: SellerTunnelStatus.success,
  property: const Property(
    id: 'property-id',
    ownerId: 'user-id',
    currentStep: 7,
    addressLabel: '12 chemin des Vignes, Chaponost',
    parcelConfirmed: true,
    propertyType: PropertyType.house,
    purchaseYear: 2012,
    constructionYear: 1998,
    livingAreaM2: 115,
    roomsCount: 5,
    heatingSystems: [HeatingSystem.heatPump],
    sanitation: Sanitation.mainsSewer,
    measurementMethod: MeasurementMethod.manual,
    noiseLevel: 3,
  ),
  documents: [
    _titleDeed,
    _document('d2', DocumentKind.propertyTax, status: DocumentStatus.analyzed),
    _document('d3', DocumentKind.energyBills, status: DocumentStatus.analyzing),
    _document('d4', DocumentKind.energyBills),
    _document('d5', DocumentKind.energyBills),
    _document('d6', DocumentKind.worksInvoice),
  ],
);

final PropertyDocument _newDocument = _document(
  'new',
  DocumentKind.identityDocument,
  fileName: 'photo.jpg',
);

Finder _row(String title) => find.widgetWithText(RealestyListItem, title);

Finder _button(String label) => find.widgetWithText(RealestyButton, label);

/// The "Scanner"/"Importer" link of a row.
Finder _link(String semanticLabel) => find.byWidgetPredicate(
  (w) => w is RealestyPressable && w.semanticLabel == semanticLabel,
);

final _pdf = Uint8List.fromList([1, 2, 3]);

void main() {
  late MockPropertyRepository repository;
  late _MockDocumentPicker picker;
  late _MockScanPdfBuilder pdfBuilder;
  late List<Uri> opened;

  setUpAll(() async {
    await loadRealestyFonts();
    registerFallbackValue(DocumentSource.files);
    registerFallbackValue(DocumentKind.other);
    registerFallbackValue(_titleDeed);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    repository = MockPropertyRepository();
    picker = _MockDocumentPicker();
    pdfBuilder = _MockScanPdfBuilder();
    opened = [];
    when(() => picker.pick(any())).thenAnswer(
      (_) async => XFile.fromData(Uint8List(10), path: '/tmp/photo.jpg'),
    );
    when(() => picker.scanPages(maxPages: any(named: 'maxPages'))).thenAnswer(
      (_) async => [XFile.fromData(Uint8List(4), path: 'page-1.jpg')],
    );
    when(() => pdfBuilder.build(any(), maxBytes: any(named: 'maxBytes')))
        .thenAnswer((_) async => _pdf);
    when(
      () => repository.uploadDocument(
        ownerId: any(named: 'ownerId'),
        propertyId: any(named: 'propertyId'),
        kind: any(named: 'kind'),
        fileName: any(named: 'fileName'),
        bytes: any(named: 'bytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async => _newDocument);
    when(() => repository.deleteDocument(any())).thenAnswer((_) async {});
    when(
      () =>
          repository.getDocumentUrl(any(), expiresIn: any(named: 'expiresIn')),
    ).thenAnswer((_) async => 'https://storage.example/signed');
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    SellerTunnelState? state,
    double height = 3000,
    MockGoRouter? goRouter,
  }) async {
    final view = tester.view
      ..physicalSize = Size(390, height)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(state ?? _mockupState);
    await tester.pumpTunnelPage(
      DocumentsPage(
        documentPicker: picker,
        scanPdfBuilder: pdfBuilder,
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
      goRouter: goRouter,
    );
    return cubit;
  }

  void verifyUpload(DocumentKind kind, {bool scanned = false}) => verify(
    () => repository.uploadDocument(
      ownerId: 'user-id',
      propertyId: 'property-id',
      kind: kind,
      fileName: scanned
          ? any(named: 'fileName', that: endsWith('.pdf'))
          : 'photo.jpg',
      bytes: scanned ? _pdf : any(named: 'bytes'),
      mimeType: scanned ? 'application/pdf' : 'image/jpeg',
    ),
  ).called(1);

  /// Scans one page of a document of the row [kind], then "Terminer".
  Future<void> scan(WidgetTester tester, String kind) async {
    final link = find.bySemanticsLabel('Scanner · $kind');
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(DocumentScanView), findsOneWidget);
    await tester.tap(_button('Terminer'));
    await tester.pumpAndSettle();
  }

  group(DocumentsPage, () {
    test('opens the documents with url_launcher by default', () {
      expect(const DocumentsPage().openUrl, isNotNull);
      expect(const DocumentsPage().documentPicker, isNull);
      expect(const DocumentsPage().scanPdfBuilder, isNull);
    });

    testWidgets('uses the device pickers by default', (tester) async {
      await tester.pumpTunnelPage(
        const DocumentsPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(_mockupState),
      );
      expect(find.byType(DocumentsView), findsOneWidget);
      final context = tester.element(find.byType(DocumentsView));
      expect(context.read<DocumentPicker>(), isA<PlatformDocumentPicker>());
      expect(context.read<ScanPdfBuilder>(), isA<IsolateScanPdfBuilder>());
    });

    testWidgets('shows the documents, their statuses and the score', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Étape 7 · Documents'), findsOneWidget);
      expect(find.text('7/7'), findsOneWidget);
      expect(
        find.text(
          'Dernière étape$_nbsp: vos documents. Scannez-les ou '
          'importez-les$_nbsp: l’expert s’en sert pour vérifier votre '
          'dossier.',
        ),
        findsOneWidget,
      );
      // Documents 45/80 of 70 + answers 30.
      expect(
        tester
            .widget<TransparencyScoreCard>(find.byType(TransparencyScoreCard))
            .score,
        69,
      );
      expect(find.text('69'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Score de transparence$_nbsp: 69 sur 100'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Ajoutez vos diagnostics pour renforcer la transparence de votre '
          'dossier.',
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(
          of: _row('Titre de propriété'),
          matching: find.text('Analysé'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 fichier · analysé'), findsNWidgets(2));
      expect(find.text('3 fichiers · extraction en cours'), findsOneWidget);
      expect(find.text('Analyse en cours'), findsOneWidget);
      expect(find.text('1 fichier · en attente de l’expert'), findsOneWidget);
      expect(find.text('Reçu'), findsOneWidget);
      expect(find.text('Obligatoire pour la certification'), findsOneWidget);
      expect(find.text('DPE, électricité, amiante…'), findsOneWidget);
      // The diagnostics are optional.
      expect(find.text('Manquant'), findsOneWidget);
      expect(
        find.descendant(
          of: _row('Diagnostics'),
          matching: find.text('Facultatif'),
        ),
        findsOneWidget,
      );
      expect(_row('Autre document'), findsOneWidget);
      // Every row can be scanned or imported, except a report not
      // concerned.
      for (final kind in [
        'Titre de propriété',
        'Taxe foncière',
        'Factures d’énergie',
        'Factures de travaux',
        'Pièce d’identité',
        'Diagnostics',
        'Autre document',
      ]) {
        expect(_link('Scanner · $kind'), findsOneWidget);
        expect(_link('Importer · $kind'), findsOneWidget);
      }
      expect(_link('Scanner · Rapport SPANC'), findsNothing);
      expect(find.text('Scanner'), findsNWidgets(7));
      expect(find.text('Importer'), findsNWidgets(7));
      expect(find.text('Raccordé au tout-à-l’égout'), findsOneWidget);
      expect(find.text('Non concerné'), findsOneWidget);
      expect(
        find.text('Titre de propriété et pièce d’identité requis pour l’envoi'),
        findsOneWidget,
      );
      expect(find.text('Envoyer mon dossier à l’expert'), findsOneWidget);
      expect(
        find.text(
          'Documents chiffrés, consultés uniquement par l’expert en charge '
          'de votre dossier. Vous pouvez les supprimer à tout moment.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty dossier', (tester) async {
      await pump(
        tester,
        state: const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            sanitation: Sanitation.septicTank,
          ),
        ),
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('Manquant'), findsNWidgets(4));
      expect(find.text('Facultatif'), findsNWidgets(4));
      expect(
        find.text('Obligatoire en assainissement individuel'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Titre de propriété et pièce d’identité requis$_nbsp; 2 autres '
          'documents pourront vous être redemandés',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Scanner" of a row uploads the PDF of the scanned pages', (
      tester,
    ) async {
      final tunnel = await pump(tester);

      await scan(tester, 'Pièce d’identité');

      expect(find.byType(DocumentScanView), findsNothing);
      verifyUpload(DocumentKind.identityDocument, scanned: true);
      verify(
        () => tunnel.updateChildren(
          documents: [..._mockupState.documents, _newDocument],
        ),
      ).called(1);
      expect(find.text('Document ajouté à votre dossier'), findsOneWidget);
      expect(
        find.text('Tous les documents obligatoires sont là'),
        findsOneWidget,
      );
    });

    testWidgets('a row with files can still be scanned', (tester) async {
      await pump(tester);

      await scan(tester, 'Titre de propriété');

      verifyUpload(DocumentKind.titleDeed, scanned: true);
    });

    testWidgets('an abandoned scan uploads nothing', (tester) async {
      when(() => picker.scanPages(maxPages: any(named: 'maxPages')))
          .thenAnswer((_) async => null);
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Scanner · Diagnostics'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentScanView), findsNothing);
      verifyNever(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      );
      expect(
        tester
            .widget<RealestyPressable>(_link('Scanner · Diagnostics'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('"Importer" of a row uploads a file of that kind', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Importer · Pièce d’identité'));
      await tester.pumpAndSettle();
      expect(find.text('Importer un document'), findsOneWidget);
      expect(
        find.text('PDF, JPG, PNG ou HEIC · 20${_nbsp}Mo maximum'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();

      verify(() => picker.pick(DocumentSource.files)).called(1);
      verifyUpload(DocumentKind.identityDocument);
    });

    testWidgets('dismissing the source sheet picks nothing', (tester) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Importer · Titre de propriété'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      verifyNever(() => picker.pick(any()));
    });

    testWidgets('"Importer" of the diagnostics row uploads diagnostics', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Importer · Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photothèque'));
      await tester.pumpAndSettle();

      verify(() => picker.pick(DocumentSource.photos)).called(1);
      verifyUpload(DocumentKind.diagnostics);
    });

    testWidgets('shows the file being uploaded and disables the inputs', (
      tester,
    ) async {
      final upload = Completer<PropertyDocument>();
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) => upload.future);
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Importer · Pièce d’identité'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photothèque'));
      await tester.pump();
      await tester.pump();

      expect(_row('photo.jpg'), findsOneWidget);
      expect(find.text('Envoi en cours…'), findsOneWidget);
      expect(
        tester
            .widget<RealestyPressable>(_link('Scanner · Diagnostics'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<RealestyPressable>(_link('Importer · Diagnostics'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<RealestyButton>(_button('Envoyer mon dossier à l’expert'))
            .onPressed,
        isNull,
      );

      upload.complete(_newDocument);
      await tester.pumpAndSettle();
      expect(find.text('Envoi en cours…'), findsNothing);
    });

    testWidgets('tells why a file is refused', (tester) async {
      when(() => picker.pick(any())).thenAnswer(
        (_) async => XFile.fromData(Uint8List(10), path: '/tmp/notes.docx'),
      );
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Importer · Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Format non pris en charge$_nbsp: choisissez un PDF, JPG, PNG ou '
          'HEIC.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('opens the files of a kind to open or delete them', (
      tester,
    ) async {
      final tunnel = await pump(tester);

      await tester.tap(_row('Titre de propriété'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentFilesSheet), findsOneWidget);
      expect(find.text('titre.pdf'), findsOneWidget);
      expect(find.text('Ajouté le 24/09/2026 · 1,2${_nbsp}Mo'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Ouvrir titre.pdf'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://storage.example/signed')]);
      expect(
        tester
            .widget<RealestyIconButton>(
              find.ancestor(
                of: find.bySemanticsLabel('Supprimer titre.pdf'),
                matching: find.byType(RealestyIconButton),
              ),
            )
            .icon,
        RealestyIcons.trash,
      );

      await tester.tap(find.bySemanticsLabel('Supprimer titre.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer ce document$_nbsp?'), findsOneWidget);
      expect(
        find.text(
          '«${_nbsp}titre.pdf$_nbsp» sera définitivement supprimé de votre '
          'dossier.',
        ),
        findsOneWidget,
      );
      await tester.tap(_button('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('titre.pdf'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Supprimer titre.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Supprimer'));
      await tester.pumpAndSettle();

      verify(() => repository.deleteDocument(_titleDeed)).called(1);
      verify(
        () => tunnel.updateChildren(
          documents: _mockupState.documents.skip(1).toList(),
        ),
      ).called(1);
      expect(find.byType(DocumentFilesSheet), findsNothing);
      expect(find.text('Document supprimé'), findsOneWidget);
    });

    testWidgets('shows a file being opened', (tester) async {
      final url = Completer<String>();
      when(
        () => repository.getDocumentUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenAnswer((_) => url.future);
      await pump(
        tester,
        state: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: testProperty,
          documents: [
            _titleDeed,
            const PropertyDocument(
              id: 'd9',
              propertyId: 'property-id',
              kind: DocumentKind.titleDeed,
              storagePath: 'user-id/property-id/d9',
            ),
          ],
        ),
      );

      await tester.tap(_row('Titre de propriété'));
      await tester.pumpAndSettle();
      // A file with no name, date or size.
      expect(
        find.descendant(
          of: find.byType(DocumentFilesSheet),
          matching: find.text('Titre de propriété'),
        ),
        findsNWidgets(2),
      );
      await tester.tap(find.bySemanticsLabel('Ouvrir titre.pdf'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(DocumentFilesSheet),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final deletes = tester.widgetList<RealestyIconButton>(
        find.byWidgetPredicate(
          (w) =>
              w is RealestyIconButton &&
              w.semanticLabel.startsWith('Supprimer'),
        ),
      );
      expect(deletes.single.onPressed, isNull);

      url.complete('https://storage.example/signed');
      await tester.pumpAndSettle();
    });

    testWidgets('tells when a document cannot be opened', (tester) async {
      when(
        () => repository.getDocumentUrl(
          any(),
          expiresIn: any(named: 'expiresIn'),
        ),
      ).thenThrow(const PropertyLoadFailure());
      await pump(tester);

      await tester.tap(_row('Titre de propriété'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Ouvrir titre.pdf'));
      await tester.pumpAndSettle();

      expect(
        find.text('Impossible d’ouvrir ce document. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('shows a failed deletion in the files sheet', (tester) async {
      when(() => repository.deleteDocument(any()))
          .thenThrow(const PropertyDeleteFailure());
      when(() => repository.getDocuments(any()))
          .thenAnswer((_) async => _mockupState.documents);
      await pump(tester);

      await tester.tap(_row('Titre de propriété'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Supprimer titre.pdf'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Supprimer'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(DocumentFilesSheet),
          matching: find.text('La suppression a échoué. Réessayez.'),
        ),
        findsOneWidget,
      );
      expect(find.text('titre.pdf'), findsOneWidget);
    });

    testWidgets('a dossier taken over by the expert is read-only', (
      tester,
    ) async {
      await pump(
        tester,
        state: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: const Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.inReview,
            currentStep: 8,
          ),
          documents: [_titleDeed],
        ),
      );

      expect(
        find.text('Votre dossier est en cours d’examen par l’expert'),
        findsOneWidget,
      );
      // No "Scanner"/"Importer" link, no hint about the sending, no
      // promise of deletion.
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).hint,
        isNull,
      );
      expect(
        find.text(
          'Documents chiffrés, consultés uniquement par l’expert en charge '
          'de votre dossier.',
        ),
        findsOneWidget,
      );
      expect(find.text('Scanner'), findsNothing);
      expect(find.text('Importer'), findsNothing);
      expect(
        tester
            .widget<RealestyButton>(_button('Envoyer mon dossier à l’expert'))
            .onPressed,
        isNull,
      );

      // The files can still be opened, not deleted.
      await tester.tap(_row('Titre de propriété'));
      await tester.pumpAndSettle();
      final delete = tester.widget<RealestyIconButton>(
        find.byWidgetPredicate(
          (w) =>
              w is RealestyIconButton &&
              w.semanticLabel == 'Supprimer titre.pdf',
        ),
      );
      expect(delete.onPressed, isNull);
      await tester.tap(find.bySemanticsLabel('Ouvrir titre.pdf'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
    });

    testWidgets('row links have a 44 px touch target', (tester) async {
      await pump(tester);

      for (final label in [
        'Scanner · Pièce d’identité',
        'Importer · Pièce d’identité',
      ]) {
        final size = tester.getSize(find.bySemanticsLabel(label));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, greaterThanOrEqualTo(44));
      }
      // Side by side, under the title.
      final scanLink = tester.getRect(
        find.bySemanticsLabel('Scanner · Pièce d’identité'),
      );
      final importLink = tester.getRect(
        find.bySemanticsLabel('Importer · Pièce d’identité'),
      );
      expect(importLink.left, greaterThanOrEqualTo(scanLink.right));
      expect(importLink.top, scanLink.top);
    });

    testWidgets('congratulates a complete dossier', (tester) async {
      await pump(
        tester,
        state: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: _mockupState.property,
          documents: [
            for (final (index, kind) in DocumentKind.values.indexed)
              _document('d$index', kind),
          ],
        ),
      );

      expect(
        find.text(
          'Tous vos documents sont là$_nbsp: votre dossier est complet.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Tous les documents obligatoires sont là'),
        findsOneWidget,
      );
      expect(find.text('100'), findsOneWidget);
      expect(_row('Plan'), findsOneWidget);
      expect(_row('Autre document'), findsOneWidget);
    });

    testWidgets('"Envoyer mon dossier" needs the title deed and the identity '
        'document', (tester) async {
      final tunnel = await pump(
        tester,
        height: 844,
        state: const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            currentStep: 7,
            sanitation: Sanitation.mainsSewer,
          ),
        ),
      );
      expect(
        find.text('Indispensable pour envoyer votre dossier'),
        findsNothing,
      );

      await tester.tap(_button('Envoyer mon dossier à l’expert'));
      await tester.pumpAndSettle();
      verifyNever(() => tunnel.saveAndContinue(any(), any()));
      expect(
        find.text(
          'Pour envoyer votre dossier, ajoutez votre titre de propriété et '
          'votre pièce d’identité.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Indispensable pour envoyer votre dossier'),
        findsNWidgets(2),
      );
      // The first one is revealed.
      expect(_row('Titre de propriété').hitTestable(), findsOneWidget);

      // Adding the identity document leaves the title deed.
      await scan(tester, 'Pièce d’identité');
      verifyUpload(DocumentKind.identityDocument, scanned: true);
      expect(
        find.text(
          'Pour envoyer votre dossier, ajoutez votre titre de propriété.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Indispensable pour envoyer votre dossier'),
        findsOneWidget,
      );
      expect(
        find.text('Titre de propriété et pièce d’identité requis pour l’envoi'),
        findsNothing,
      );
      // Once the "uploaded" snackbar is gone.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(_button('Envoyer mon dossier à l’expert'));
      await tester.pumpAndSettle();
      verifyNever(() => tunnel.saveAndContinue(any(), any()));
    });

    testWidgets('"Envoyer mon dossier" submits the dossier', (tester) async {
      final tunnel = await pump(
        tester,
        state: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: _mockupState.property,
          documents: [..._mockupState.documents, _newDocument],
        ),
      );
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).trailingIcon,
        RealestyIcons.chevronRight,
      );

      await tester.tap(_button('Envoyer mon dossier à l’expert'));
      await tester.pump();

      final patch =
          verify(
                () => tunnel.saveAndContinue(
                  SellerTunnelStep.documents,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch[PropertyColumns.status], PropertyStatus.submitted);
      expect(patch[PropertyColumns.submittedAt], isA<DateTime>());
      expect(patch[PropertyColumns.transparencyScore], 83);
    });

    testWidgets('a dossier sent again keeps its submission date', (
      tester,
    ) async {
      final tunnel = await pump(
        tester,
        state: SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: 'property-id',
            ownerId: 'user-id',
            status: PropertyStatus.submitted,
            currentStep: 8,
            submittedAt: DateTime.utc(2026, 9, 24),
          ),
          documents: [_titleDeed, _newDocument],
        ),
      );

      await tester.tap(_button('Envoyer mon dossier à l’expert'));
      await tester.pump();

      final patch =
          verify(
                () => tunnel.saveAndContinue(
                  SellerTunnelStep.documents,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch.containsKey(PropertyColumns.submittedAt), isFalse);
      expect(patch[PropertyColumns.status], PropertyStatus.submitted);
    });

    testWidgets('sends back to the unfinished step', (tester) async {
      final goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      final tunnel = await pump(
        tester,
        goRouter: goRouter,
        state: const SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(id: 'p', ownerId: 'u', currentStep: 4),
        ),
      );

      await tester.tap(_button('Envoyer mon dossier à l’expert'));
      await tester.pump();

      verify(() => goRouter.go(AppRoutes.sellerTechnical)).called(1);
      verifyNever(() => tunnel.saveAndContinue(any(), any()));
      expect(
        find.text(
          'Terminez d’abord les étapes précédentes$_nbsp: votre dossier '
          'n’est pas encore complet.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('disables the inputs while the dossier is being saved', (
      tester,
    ) async {
      await pump(
        tester,
        state: SellerTunnelState(
          status: SellerTunnelStatus.success,
          saveStatus: SellerTunnelSaveStatus.inProgress,
          property: _mockupState.property,
          documents: _mockupState.documents,
        ),
      );

      expect(
        tester
            .widget<RealestyPressable>(_link('Scanner · Diagnostics'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<RealestyListItem>(_row('Titre de propriété')).onTap,
        isNull,
      );
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
    });

    testWidgets('a failed scan can be retried or removed', (tester) async {
      var uploads = 0;
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async {
        if (uploads++ < 2) throw const DocumentUploadFailure();
        return _newDocument;
      });
      when(() => repository.getDocuments(any()))
          .thenAnswer((_) async => _mockupState.documents);
      final tunnel = await pump(tester);

      await scan(tester, 'Pièce d’identité');
      expect(
        find.text(
          'L’envoi du document a échoué. Vérifiez votre connexion, puis '
          'touchez «${_nbsp}Réessayer$_nbsp».',
        ),
        findsOneWidget,
      );
      expect(find.text('Pièce d’identité · échec de l’envoi'), findsOneWidget);

      // Not sent while a file would be lost.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(_button('Envoyer mon dossier à l’expert'));
      await tester.pump();
      expect(
        find.text(
          'Un document n’a pas pu être envoyé$_nbsp: réessayez ou '
          'retirez-le avant d’envoyer votre dossier.',
        ),
        findsOneWidget,
      );
      verifyNever(() => tunnel.saveAndContinue(any(), any()));

      final retry = find.byWidgetPredicate(
        (w) =>
            w is RealestyPressable &&
            (w.semanticLabel?.startsWith('Réessayer l’envoi de') ?? false),
      );
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(uploads, 2);
      expect(find.text('Pièce d’identité · échec de l’envoi'), findsOneWidget);

      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(uploads, 3);
      expect(find.text('Pièce d’identité · échec de l’envoi'), findsNothing);
      expect(find.text('Document ajouté à votre dossier'), findsOneWidget);
    });

    testWidgets('a failed upload can be removed', (tester) async {
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenThrow(const DocumentUploadFailure());
      when(() => repository.getDocuments(any()))
          .thenAnswer((_) async => _mockupState.documents);
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Importer · Diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics · échec de l’envoi'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Retirer photo.jpg'));
      await tester.pumpAndSettle();
      expect(find.text('Diagnostics · échec de l’envoi'), findsNothing);
    });

    testWidgets('shortens the send button with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);

      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).label,
        'Envoyer à l’expert',
      );
    });

    testWidgets('back goes to V6', (tester) async {
      final goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      await pump(tester, goRouter: goRouter);

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.sellerLifestyle)).called(1);
    });
  });
}
