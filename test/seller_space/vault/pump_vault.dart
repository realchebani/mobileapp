import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/vault/vault.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/document_picker.dart';
import 'package:mobileapp/seller_tunnel/steps/documents/data/scan_pdf_builder.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';
import '../pump_seller_space.dart';
import 'vault_fixtures.dart';

class MockDocumentPicker extends Mock implements DocumentPicker;

class FakeScanPdfBuilder implements ScanPdfBuilder {
  @override
  Future<Uint8List> build(
    List<Uint8List> pages, {
    required int maxBytes,
  }) async => Uint8List.fromList([9]);
}

/// The mocks of a vault test.
class VaultTestKit {
  new() {
    registerFallbackValue(DocumentKind.other);
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(document('fallback'));
    registerFallbackValue(DocumentSource.files);
    registerFallbackValue(<DocumentVisibility>{});
    registerFallbackValue(Duration.zero);
    when(() => repository.getDocumentsOf(any()))
        .thenAnswer((_) async => documents);
    when(() => repository.getDocuments(any()))
        .thenAnswer((_) async => documents);
    when(() => repository.getOwners(any())).thenAnswer((_) async => owners);
    when(() => valuations.getLatestValuation(any()))
        .thenAnswer((_) async => valuation);
    when(() => router.push<Object?>(any())).thenAnswer((_) async => null);
    when(() => router.go(any())).thenReturn(null);
    when(router.canPop).thenReturn(true);
    when(router.pop).thenReturn(null);
  }

  final repository = MockPropertyRepository();
  final valuations = MockValuationRepository();
  final picker = MockDocumentPicker();
  final router = MockGoRouter();
  List<PropertyDocument> documents = [];
  List<PropertyOwner> owners = const [sophie, marc];
  Valuation? valuation = testValuation;
  final opened = <Uri>[];
  final shared = <String>[];

  VaultServices get services => VaultServices(
    documentPicker: picker,
    scanPdfBuilder: FakeScanPdfBuilder(),
    openUrl: (uri) async {
      opened.add(uri);
      return true;
    },
    share: (bytes, name, mime) async => shared.add(name),
  );

  void uploads(PropertyDocument result) => when(
    () => repository.uploadDocument(
      ownerId: any(named: 'ownerId'),
      propertyId: any(named: 'propertyId'),
      kind: any(named: 'kind'),
      fileName: any(named: 'fileName'),
      bytes: any(named: 'bytes'),
      mimeType: any(named: 'mimeType'),
      title: any(named: 'title'),
      ownerRef: any(named: 'ownerRef'),
    ),
  ).thenAnswer((_) async => result);

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    List<Property> properties = const [sentProperty],
    List<PropertyLot> lots = const [],
    SellerPropertiesCubit? propertiesCubit,
    GoRouter? goRouter,
    double height = 844,
  }) async {
    usePhoneSurface();
    tester.view.physicalSize = Size(390, height);
    await tester.pumpSellerSpacePage(
      page,
      sellerPropertiesCubit:
          propertiesCubit ??
          mockSellerPropertiesCubit(properties: properties, lots: lots),
      propertyRepository: repository,
      valuationRepository: valuations,
      goRouter: goRouter ?? router,
    );
    await tester.pumpAndSettle();
  }
}
