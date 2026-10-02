import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/method/plan/plan_review_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

class _MockDocumentPicker extends Mock implements DocumentPicker;

const _nbsp = ' ';

const _plan = PropertyDocument(
  id: 'plan-doc',
  propertyId: 'property-id',
  kind: DocumentKind.plan,
  storagePath: 'user-id/property-id/1_plan.jpg',
);

const _existing = Room(
  id: 'old',
  propertyId: 'property-id',
  name: 'Cave',
  areaM2: 5,
);

void main() {
  late _MockDocumentPicker picker;
  late MockPropertyRepository repository;
  late MockSellerTunnelCubit tunnel;

  setUpAll(() {
    registerFallbackValue(DocumentKind.plan);
    registerFallbackValue(DocumentSource.photos);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const Room(propertyId: 'p', name: 'x', areaM2: 1));
  });

  setUp(() {
    picker = _MockDocumentPicker();
    when(() => picker.scanPages(maxPages: 1)).thenAnswer(
      (_) async => [
        XFile.fromData(Uint8List.fromList([1]), name: 'p.jpg'),
      ],
    );
    when(() => picker.pick(DocumentSource.photos)).thenAnswer(
      (_) async => XFile.fromData(Uint8List.fromList([2]), name: 'p.jpg'),
    );
    repository = MockPropertyRepository();
    when(
      () => repository.uploadDocument(
        ownerId: any(named: 'ownerId'),
        propertyId: any(named: 'propertyId'),
        kind: any(named: 'kind'),
        fileName: any(named: 'fileName'),
        bytes: any(named: 'bytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async => _plan);
    when(() => repository.readPlan(any())).thenAnswer(
      (_) async => const PlanReading(
        isFloorPlan: true,
        rooms: [PlanRoom(name: 'Séjour', areaM2: 25, kind: 'livingRoom')],
      ),
    );
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
    tunnel = mockSellerTunnelCubit(
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: testProperty,
        rooms: [_existing],
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    PhotoAnalysisConsent consent = PhotoAnalysisConsent.given,
  }) async {
    usePhoneSurface();
    await tester.pumpTunnelPage(
      MethodPage(documentPicker: picker, encodePlan: (image) async => image),
      sellerTunnelCubit: tunnel,
      propertyRepository: repository,
      photoServices: await testPhotoServices(consent: consent),
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('MethodPage · Lire un plan', () {
    testWidgets('scans the plan, reviews it and adds the rooms', (
      tester,
    ) async {
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      expect(find.text('Votre plan'), findsOneWidget);
      await tap(tester, find.text('Scanner le plan'));
      expect(find.byType(PlanReviewPage), findsOneWidget);
      verify(
        () => repository.uploadDocument(
          ownerId: 'user-id',
          propertyId: 'property-id',
          kind: DocumentKind.plan,
          fileName: 'plan.jpg',
          bytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
        ),
      ).called(1);
      verify(() => tunnel.updateChildren(documents: const [_plan])).called(1);
      await tap(tester, find.text('Ajouter 1 pièce'));
      final saved =
          verify(() => repository.saveRoom(captureAny())).captured.single
              as Room;
      expect(saved.source, RoomSource.plan);
      expect(saved.sortOrder, 1);
      verify(() => tunnel.updateChildren(rooms: [_existing, saved])).called(1);
      verify(
        () => tunnel.saveAndContinue(SellerTunnelStep.method, {
          PropertyColumns.measurementMethod: MeasurementMethod.plan,
        }),
      ).called(1);
    });

    testWidgets('without the vision AI the plan is only filed', (tester) async {
      await pump(tester, consent: PhotoAnalysisConsent.declined);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Choisir une photo'));
      expect(find.byType(PhotoConsentPage), findsOneWidget);
      await tap(tester, find.text('Continuer sans l’IA'));
      expect(
        find.text(
          'Plan déposé pour l’expert. Saisissez maintenant vos pièces.',
        ),
        findsOneWidget,
      );
      verifyNever(() => repository.readPlan(any()));
      verify(
        () => tunnel.saveAndContinue(SellerTunnelStep.method, {
          PropertyColumns.measurementMethod: MeasurementMethod.plan,
        }),
      ).called(1);
    });

    testWidgets('a dismissed sheet or a cancelled scan changes nothing', (
      tester,
    ) async {
      when(() => picker.scanPages(maxPages: 1)).thenAnswer((_) async => null);
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
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
    });

    testWidgets('tells a refused access and a failed pick', (tester) async {
      when(() => picker.scanPages(maxPages: 1))
          .thenThrow(const DocumentAccessDenied('x'));
      when(() => picker.pick(any())).thenThrow(Exception());
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      expect(
        find.text(
          'Accès refusé$_nbsp: autorisez l’appareil photo ou les photos '
          'dans les Réglages.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Choisir une photo'));
      expect(
        find.text('Le plan n’a pas pu être envoyé. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('tells a failed upload', (tester) async {
      when(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenThrow(Exception());
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      expect(
        find.text('Le plan n’a pas pu être envoyé. Réessayez.'),
        findsOneWidget,
      );
      verifyNever(() => repository.readPlan(any()));
    });

    testWidgets('tells a failed reading and the quota', (tester) async {
      when(() => repository.readPlan(any())).thenThrow(Exception());
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      expect(
        find.text(
          'Le plan n’a pas pu être lu. Réessayez, ou saisissez vos pièces.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      when(() => repository.readPlan(any()))
          .thenThrow(const VisionQuotaFailure('x'));
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      expect(find.textContaining('Limite de lectures de plan'), findsOneWidget);
    });

    testWidgets('a failed reading is read again without a new upload', (
      tester,
    ) async {
      var reads = 0;
      when(() => repository.readPlan(any())).thenAnswer((_) async {
        if (reads++ == 0) throw Exception();
        return const PlanReading(isFloorPlan: false);
      });
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      expect(find.text('Relire le dernier plan'), findsNothing);
      await tap(tester, find.text('Scanner le plan'));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Relire le dernier plan'));
      expect(find.byType(PlanReviewPage), findsOneWidget);
      verify(
        () => repository.uploadDocument(
          ownerId: any(named: 'ownerId'),
          propertyId: any(named: 'propertyId'),
          kind: any(named: 'kind'),
          fileName: any(named: 'fileName'),
          bytes: any(named: 'bytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).called(1);
      verify(() => repository.readPlan('plan-doc')).called(2);
    });

    testWidgets('the rooms read can replace the existing ones', (tester) async {
      when(() => repository.deleteRoomPhotos(any())).thenAnswer((_) async {});
      when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      await tap(tester, find.text('Remplacer mes pièces'));
      await tap(tester, find.text('Ajouter 1 pièce'));
      verify(() => repository.deleteRoom('old')).called(1);
      verify(() => tunnel.updateChildren(rooms: const [])).called(1);
      verify(
        () => tunnel.saveAndContinue(SellerTunnelStep.method, {
          PropertyColumns.measurementMethod: MeasurementMethod.plan,
        }),
      ).called(1);
    });

    testWidgets('"Saisir mes pièces" continues by hand', (tester) async {
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      await tap(tester, find.text('Saisir mes pièces'));
      verify(
        () => tunnel.saveAndContinue(SellerTunnelStep.method, {
          PropertyColumns.measurementMethod: MeasurementMethod.manual,
        }),
      ).called(1);
    });

    testWidgets('back from the review changes nothing', (tester) async {
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      await tap(tester, find.bySemanticsLabel('Retour').last);
      verifyNever(() => tunnel.saveAndContinue(any(), any()));
    });

    testWidgets('tells rooms that could not be saved', (tester) async {
      when(() => repository.saveRoom(any())).thenThrow(Exception());
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tap(tester, find.text('Scanner le plan'));
      await tap(tester, find.text('Ajouter 1 pièce'));
      expect(
        find.text('Les pièces n’ont pas pu être enregistrées. Réessayez.'),
        findsOneWidget,
      );
      verifyNever(() => tunnel.saveAndContinue(any(), any()));
    });

    testWidgets('shows the progress and disables the cards', (tester) async {
      final upload = Completer<PropertyDocument>();
      final read = Completer<PlanReading>();
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
      when(() => repository.readPlan(any())).thenAnswer((_) => read.future);
      await pump(tester);
      await tap(tester, find.text('Lire un plan'));
      await tester.tap(find.text('Scanner le plan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Envoi du plan…'), findsOneWidget);
      upload.complete(_plan);
      await tester.pump();
      await tester.pump();
      expect(find.text('Lecture du plan…'), findsOneWidget);
      read.complete(const PlanReading(isFloorPlan: false));
      await tester.pumpAndSettle();
      expect(find.byType(PlanReviewPage), findsOneWidget);
    });
  });
}
