import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_editor_page.dart';
import 'package:mobileapp/seller_space/sale/listing/photos/listing_photos_page.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mobileapp/seller_space/sale/sale_activation_page.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import 'sale_helpers.dart';

/// The sale screens at a text scale of 1.3 (iOS « larger text »): any
/// overflow fails the test.
void main() {
  setUpAll(loadRealestyFonts);

  late MockSaleRepository repository;

  setUp(() {
    repository = MockSaleRepository();
    when(() => repository.getListingPhotos(any())).thenAnswer(
      (_) async => [
        for (var i = 0; i < 6; i++)
          ListingPhoto(
            id: 'p$i',
            saleId: 'sale-id',
            storagePath: 'user-id/sale-id/p$i.jpg',
            caption: 'Séjour avec une très longue légende',
          ),
      ],
    );
    when(() => repository.listingPhotoUrls(any())).thenAnswer((_) async => {});
  });

  void scale(WidgetTester tester) {
    usePhoneSurface();
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  const signed = Sale(
    id: 'sale-id',
    propertyId: 'property-id',
    formula: SaleFormula.premium,
    stage: SaleStage.published,
    askingPriceEur: 525000,
    listingTitle: 'Maison',
    listingDescription: 'Texte',
  );

  for (final formula in SaleFormula.values) {
    testWidgets('activation ${formula.name}', (tester) async {
      scale(tester);
      await tester.pumpSalePage(
        const SaleActivationPage(),
        saleCubit: mockSaleCubit(
          saleState(
            sale: Sale(
              id: 'sale-id',
              propertyId: 'property-id',
              formula: formula,
              stage: SaleStage.planChosen,
              askingPriceEur: 525000,
            ),
          ),
        ),
        goRouter: saleRouter(),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('listing editor and photos', (tester) async {
    scale(tester);
    await tester.pumpSalePage(
      const ListingEditorPage(),
      saleCubit: mockSaleCubit(saleState(sale: signed)),
      saleRepository: repository,
      goRouter: saleRouter(),
    );
    await tester.pumpAndSettle();
    await tester.pumpSalePage(
      ListingPhotosPage(key: UniqueKey()),
      saleCubit: mockSaleCubit(saleState(sale: signed)),
      saleRepository: repository,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('V10 sheet', (tester) async {
    scale(tester);
    final valuations = MockValuationRepository();
    when(() => valuations.getLatestValuation(any()))
        .thenAnswer((_) async => null);
    await tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<SellerPropertiesCubit>.value(value: propertiesCubit()),
          BlocProvider<SalesCubit>.value(value: salesCubit()),
        ],
        child: const Scaffold(body: Text('x')),
      ),
      saleRepository: repository,
      valuationRepository: valuations,
      goRouter: saleRouter(),
    );
    final context = tester.element(find.text('x'));
    final property = propertiesCubit().state.properties.single;
    startSaleFor(context, property);
    await tester.pumpAndSettle();
    for (final tab in ['1 %', 'Premium', '3 %']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
