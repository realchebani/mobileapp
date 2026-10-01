import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_files_sheet.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/document_option_sheets.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/widgets/transparency_score_card.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

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
    heatingEnergy: HeatingEnergy.heatPump,
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

void main() {
  late MockPropertyRepository repository;
  late _MockDocumentPicker picker;
  late List<Uri> opened;

  setUpAll(() {
    registerFallbackValue(DocumentSource.camera);
    registerFallbackValue(DocumentKind.other);
    registerFallbackValue(_titleDeed);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
  });

  setUp(() {
    repository = MockPropertyRepository();
    picker = _MockDocumentPicker();
    opened = [];
    when(() => picker.pick(any())).thenAnswer(
      (_) async => XFile.fromData(Uint8List(10), path: '/tmp/photo.jpg'),
    );
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

  void verifyUpload(DocumentKind kind) => verify(
    () => repository.uploadDocument(
      ownerId: 'user-id',
      propertyId: 'property-id',
      kind: kind,
      fileName: 'photo.jpg',
      bytes: any(named: 'bytes'),
      mimeType: 'image/jpeg',
    ),
  ).called(1);

  group(DocumentsPage, () {
    test('opens the documents with url_launcher by default', () {
      expect(const DocumentsPage().openUrl, isNotNull);
      expect(const DocumentsPage().documentPicker, isNull);
    });

    testWidgets('uses the device pickers by default', (tester) async {
      await tester.pumpTunnelPage(
        const DocumentsPage(),
        sellerTunnelCubit: mockSellerTunnelCubit(_mockupState),
      );
      expect(find.byType(DocumentsView), findsOneWidget);
    });

    testWidgets('shows the documents, their statuses and the score', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Étape 7 · Documents'), findsOneWidget);
      expect(find.text('7/7'), findsOneWidget);
      expect(
        find.text(
          'Dernière étape$_nbsp: vos documents. Photographiez-les ou '
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
      expect(find.text('Manquant'), findsNWidgets(2));
      expect(find.text('Raccordé au tout-à-l’égout'), findsOneWidget);
      expect(find.text('Non concerné'), findsOneWidget);
      expect(
        find.text(
          '2 documents manquants$_nbsp: l’expert pourra vous les redemander',
        ),
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
      expect(find.text('Manquant'), findsNWidgets(5));
      expect(find.text('Facultatif'), findsNWidgets(2));
      expect(
        find.text('Obligatoire en assainissement individuel'),
        findsOneWidget,
      );
      expect(
        find.text(
          '5 documents manquants$_nbsp: l’expert pourra vous les redemander',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Scanner" photographs a document and asks its kind', (
      tester,
    ) async {
      final tunnel = await pump(tester);

      await tester.tap(_button('Scanner'));
      await tester.pumpAndSettle();
      verify(() => picker.pick(DocumentSource.camera)).called(1);
      expect(find.text('Quel est ce document$_nbsp?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DocumentOptionSheet<DocumentKind>),
          matching: find.text('Pièce d’identité'),
        ),
      );
      await tester.pumpAndSettle();

      verifyUpload(DocumentKind.identityDocument);
      verify(
        () => tunnel.updateChildren(
          documents: [..._mockupState.documents, _newDocument],
        ),
      ).called(1);
      expect(find.text('Document ajouté à votre dossier'), findsOneWidget);
      expect(
        find.text(
          '1 document manquant$_nbsp: l’expert pourra vous le '
          'redemander',
        ),
        findsOneWidget,
      );
    });

    testWidgets('dismissing the kind sheet drops the file', (tester) async {
      await pump(tester);

      await tester.tap(_button('Scanner'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentOptionSheet<DocumentKind>), findsNothing);
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
      // The buttons are enabled again.
      expect(
        tester.widget<RealestyButton>(_button('Scanner')).onPressed,
        isNotNull,
      );
    });

    testWidgets('"Importer" picks a file, then asks its kind', (tester) async {
      await pump(tester);

      await tester.tap(_button('Importer'));
      await tester.pumpAndSettle();
      expect(find.text('Importer un document'), findsOneWidget);
      expect(
        find.text('PDF, JPG, PNG ou HEIC · 20${_nbsp}Mo maximum'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fichiers'));
      await tester.pumpAndSettle();

      verify(() => picker.pick(DocumentSource.files)).called(1);
      expect(find.byType(DocumentOptionSheet<DocumentKind>), findsOneWidget);
    });

    testWidgets('dismissing the source sheet picks nothing', (tester) async {
      await pump(tester);

      await tester.tap(_button('Importer'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      verifyNever(() => picker.pick(any()));
    });

    testWidgets('"Scanner" of a missing row uploads that kind', (tester) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Scanner · Pièce d’identité'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentOptionSheet<DocumentKind>), findsNothing);
      verifyUpload(DocumentKind.identityDocument);
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

      await tester.tap(find.bySemanticsLabel('Scanner · Pièce d’identité'));
      await tester.pump();
      await tester.pump();

      expect(_row('photo.jpg'), findsOneWidget);
      expect(find.text('Envoi en cours…'), findsOneWidget);
      expect(
        tester.widget<RealestyButton>(_button('Scanner')).onPressed,
        isNull,
      );
      expect(
        tester.widget<RealestyButton>(_button('Importer')).onPressed,
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

      await tester.tap(_button('Scanner'));
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
      for (final label in [
        'Scanner',
        'Importer',
        'Envoyer mon dossier à l’expert',
      ]) {
        expect(tester.widget<RealestyButton>(_button(label)).onPressed, isNull);
      }

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

      final size = tester.getSize(
        find.bySemanticsLabel('Scanner · Pièce d’identité'),
      );
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
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

    testWidgets('"Envoyer mon dossier" submits the dossier', (tester) async {
      final tunnel = await pump(tester);

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
      expect(patch[PropertyColumns.transparencyScore], 69);
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
        tester.widget<RealestyButton>(_button('Scanner')).onPressed,
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

    testWidgets('back goes to V6', (tester) async {
      final goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      await pump(tester, goRouter: goRouter);

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.sellerLifestyle)).called(1);
    });
  });
}
