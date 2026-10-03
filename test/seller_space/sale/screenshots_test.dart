import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_editor_page.dart';
import 'package:mobileapp/seller_space/sale/sale_activation_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import 'sale_helpers.dart';

/// Full-height renders of the sale screens for the design review (written
/// only with `--dart-define=SALE_SCREENSHOTS=<dir>`).
void main() {
  setUpAll(loadRealestyFonts);

  Sale sale(SaleFormula formula, SaleStage stage) => Sale(
    id: 'sale-id',
    propertyId: 'property-id',
    formula: formula,
    stage: stage,
    askingPriceEur: 525000,
    listingTitle: 'Maison de 115 m² à Chaponost',
    listingDescription:
        'Maison de 115 m², 5 pièces à Chaponost. Construction : 1998.',
    descriptionSource: DescriptionSource.template,
  );

  for (final (name, formula, height) in [
    ('v11_essentiel_full', SaleFormula.essentiel, 2900.0),
    ('v11b_premium_full', SaleFormula.premium, 3300.0),
    ('v11c_expert_full', SaleFormula.expert, 1900.0),
  ]) {
    testWidgets(name, (tester) async {
      useTallSurface(height);
      await tester.pumpSalePage(
        const SaleActivationPage(),
        saleCubit: mockSaleCubit(
          saleState(sale: sale(formula, SaleStage.planChosen), verified: true),
        ),
        goRouter: saleRouter(),
      );
      await tester.screenshot(name);
      expect(find.byType(SaleActivationPage), findsOneWidget);
    });
  }

  testWidgets('signature sheet', (tester) async {
    useTallSurface(2900);
    await tester.pumpSalePage(
      const SaleActivationPage(),
      saleCubit: mockSaleCubit(saleState()),
      goRouter: saleRouter(),
    );
    await tester.tap(find.text('Signer le mandat en ligne'));
    await tester.pumpAndSettle();
    usePhoneSurface();
    await tester.pumpAndSettle();
    await tester.screenshot('mandate_signature_sheet');
    expect(find.text('Signature du mandat'), findsOneWidget);
  });

  testWidgets('v11a full', (tester) async {
    useTallSurface(2000);
    final repository = MockSaleRepository();
    when(() => repository.getListingPhotos(any())).thenAnswer((_) async => []);
    when(() => repository.listingPhotoUrls(any())).thenAnswer((_) async => {});
    await tester.pumpSalePage(
      const ListingEditorPage(),
      saleCubit: mockSaleCubit(
        saleState(sale: sale(SaleFormula.premium, SaleStage.mandateSigned)),
      ),
      saleRepository: repository,
      goRouter: saleRouter(),
    );
    await tester.pumpAndSettle();
    await tester.screenshot('v11a_listing_full');
    expect(find.byType(ListingEditorPage), findsOneWidget);
  });
}
