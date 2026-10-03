import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_editor_page.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_preview_page.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../../helpers/helpers.dart';
import '../sale_helpers.dart';

const _signed = Sale(
  id: 'sale-id',
  propertyId: 'property-id',
  formula: SaleFormula.essentiel,
  stage: SaleStage.mandateSigned,
  askingPriceEur: 525000,
  listingTitle: 'Maison de 115 m² à Chaponost',
  listingDescription: 'Maison familiale.',
  descriptionSource: DescriptionSource.template,
);

ListingPhoto _photo(int i) => ListingPhoto(
  id: 'p$i',
  saleId: 'sale-id',
  storagePath: 'user-id/sale-id/p$i.jpg',
  sortOrder: i,
);

void main() {
  setUpAll(loadRealestyFonts);

  late MockSaleRepository repository;
  late MockGoRouter router;

  setUp(() {
    repository = MockSaleRepository();
    router = saleRouter();
    when(() => repository.getListingPhotos('sale-id'))
        .thenAnswer((_) async => [for (var i = 0; i < 6; i++) _photo(i)]);
    when(() => repository.listingPhotoUrls(any())).thenAnswer((_) async => {});
  });

  Future<MockSaleCubit> pump(
    WidgetTester tester,
    SaleState state, {
    Widget page = const ListingEditorPage(),
    bool tall = true,
  }) async {
    if (tall) {
      useTallSurface();
    } else {
      usePhoneSurface();
    }
    final cubit = mockSaleCubit(state);
    await tester.pumpSalePage(
      page,
      saleCubit: cubit,
      saleRepository: repository,
      goRouter: router,
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  group(ListingEditorPage, () {
    testWidgets('screenshot', (tester) async {
      await pump(tester, saleState(sale: _signed), tall: false);
      expect(find.text('Votre annonce est prête'), findsOneWidget);
      await tester.screenshot('v11a_listing');
    });

    testWidgets('not signed, or L’Expert: nothing to edit', (tester) async {
      await pump(tester, saleState());
      expect(find.text('Signez d’abord votre mandat.'), findsOneWidget);
      await tester.tap(find.text('Voir ma formule'));
      verify(() => router.go('/vendeur/ventes/sale-id')).called(1);
      await pump(
        tester,
        saleState(
          sale: const Sale(
            id: 'sale-id',
            formula: SaleFormula.expert,
            stage: SaleStage.mandateSigned,
          ),
        ),
      );
      expect(find.textContaining('votre agent prépare'), findsOneWidget);
    });

    testWidgets('generates the text once, with the price', (tester) async {
      final cubit = await pump(
        tester,
        saleState(
          sale: const Sale(
            id: 'sale-id',
            propertyId: 'property-id',
            formula: SaleFormula.premium,
            stage: SaleStage.mandateSigned,
          ),
        ),
      );
      final patch =
          verify(() => cubit.updateListing(captureAny())).captured.single
              as Map<String, Object?>;
      expect(patch['listing_title'], 'Maison de 115 m² à Chaponost');
      expect(patch['description_source'], 'template');
      expect(patch['asking_price_eur'], 525000);
      expect(find.text('Description à rédiger'), findsOneWidget);
      expect(find.text('Dans la fourchette'), findsOneWidget);
    });

    testWidgets('photos strip, manage, preview', (tester) async {
      await pump(tester, saleState(sale: _signed));
      expect(find.text('6 photos'), findsOneWidget);
      expect(find.text('+ 2'), findsOneWidget);
      await tester.tap(find.text('Gérer les photos'));
      await tester.pumpAndSettle();
      verify(
        () => router.push<Object?>('/vendeur/ventes/sale-id/annonce/photos'),
      ).called(1);
      await tester.tap(find.bySemanticsLabel('Aperçu'));
      verify(
        () => router.push<Object?>('/vendeur/ventes/sale-id/annonce/apercu'),
      ).called(1);
    });

    testWidgets('photos that cannot be read leave the strip empty', (
      tester,
    ) async {
      when(() => repository.getListingPhotos('sale-id')).thenThrow(Exception());
      await pump(tester, saleState(sale: _signed));
      expect(find.text('Aucune photo'), findsOneWidget);
    });

    testWidgets('price: typed, out of range, invalid, saved later', (
      tester,
    ) async {
      final cubit = await pump(tester, saleState(sale: _signed));
      await tester.enterText(find.byType(TextField), '600000');
      await tester.pump();
      expect(find.text('Hors fourchette'), findsOneWidget);
      expect(find.textContaining('6 000 €'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      verify(() => cubit.updateListing({'asking_price_eur': 600000})).called(1);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(tester.widget<Slider>(find.byType(Slider)).value, 525000);
      await tester.enterText(find.byType(TextField), '500');
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Indiquez un prix'), findsOneWidget);
      verifyNever(() => cubit.updateListing({'asking_price_eur': 500}));
      await tester.tap(find.text('Publier mon annonce'));
      await tester.pump();
      verifyNever(cubit.publish);
    });

    testWidgets('price: the slider; a pending price is saved on leaving', (
      tester,
    ) async {
      final cubit = await pump(tester, saleState(sale: _signed));
      await tester.drag(find.byType(Slider), const Offset(-60, 0));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      verify(() => cubit.updateListing(any())).called(1);
    });

    testWidgets('publish: saved price, then published', (tester) async {
      final cubit = await pump(tester, saleState(sale: _signed));
      await tester.enterText(find.byType(TextField), '530000');
      await tester.tap(find.text('Publier mon annonce'));
      await tester.pumpAndSettle();
      verify(() => cubit.updateListing({'asking_price_eur': 530000})).called(1);
      verify(cubit.publish).called(1);
      expect(
        find.text('Votre annonce est en ligne dans Realesty.'),
        findsOneWidget,
      );
    });

    testWidgets('publish refused: what is missing, or why', (tester) async {
      await pump(
        tester,
        saleState(
          sale: _signed,
          failure: const SaleFailure(
            SaleFailureReason.publishIncomplete,
            missing: PublishMissing.values,
          ),
        ),
      );
      await tester.tap(find.text('Publier mon annonce'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Pour publier, il manque : le prix, le titre, la description, '
          'au moins 5 photos.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('publish refused for another reason', (tester) async {
      useTallSurface();
      final cubit = mockSaleCubit(saleState(sale: _signed));
      when(cubit.publish).thenAnswer((_) async {
        when(() => cubit.state).thenReturn(
          saleState(
            sale: _signed,
            failure: const SaleFailure(SaleFailureReason.mandateNotSigned),
          ),
        );
      });
      await tester.pumpSalePage(
        ListingEditorPage(key: UniqueKey()),
        saleCubit: cubit,
        saleRepository: repository,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '530000');
      await tester.tap(find.text('Publier mon annonce'));
      await tester.pumpAndSettle();
      verify(cubit.publish).called(1);
    });

    testWidgets('published: take offline; text by the seller', (tester) async {
      final cubit = await pump(
        tester,
        saleState(
          sale: Sale(
            id: 'sale-id',
            propertyId: 'property-id',
            formula: SaleFormula.essentiel,
            stage: SaleStage.published,
            askingPriceEur: 525000,
            listingTitle: 'T',
            listingDescription: 'D',
            descriptionSource: DescriptionSource.seller,
            publishedAt: DateTime(2026, 10, 3),
          ),
        ),
      );
      expect(find.text('Modifié par vous'), findsOneWidget);
      expect(find.text('Votre annonce est en ligne'), findsOneWidget);
      await tester.tap(find.text('Mettre hors ligne'));
      await tester.pumpAndSettle();
      verify(cubit.unpublish).called(1);
      expect(find.text('Votre annonce est hors ligne.'), findsOneWidget);
    });

    testWidgets('text sheet: errors, save, regenerate', (tester) async {
      final cubit = await pump(tester, saleState(sale: _signed));
      await tester.tap(find.text('Modifier le texte'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(ListingTextSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, ' ');
      await tester.enterText(fields.last, '');
      await tester.tap(find.text('Enregistrer'));
      await tester.pump();
      expect(find.text('le titre'), findsOneWidget);
      expect(find.text('la description'), findsOneWidget);
      await tester.enterText(fields.first, 'Belle maison');
      await tester.enterText(fields.last, 'Au calme.');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      verify(
        () => cubit.updateListing({
          'listing_title': 'Belle maison',
          'listing_description': 'Au calme.',
          'description_source': 'seller',
        }),
      ).called(1);
      expect(find.byType(ListingTextSheet), findsNothing);
      await tester.tap(find.text('Modifier le texte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Régénérer depuis mon dossier'));
      await tester.pumpAndSettle();
      final patch =
          verify(() => cubit.updateListing(captureAny())).captured.last
              as Map<String, Object?>;
      expect(patch['description_source'], 'template');
    });

    testWidgets('text sheet: a refused save keeps the sheet', (tester) async {
      await pump(
        tester,
        saleState(
          sale: _signed,
          failure: const SaleFailure(SaleFailureReason.unknown),
        ),
      );
      await tester.tap(find.text('Modifier le texte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.byType(ListingTextSheet), findsOneWidget);
    });

    testWidgets('pull to refresh', (tester) async {
      final cubit = await pump(tester, saleState(sale: _signed), tall: false);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      verify(cubit.refresh).called(1);
    });
  });

  group(ListingPreviewPage, () {
    testWidgets('what buyers see', (tester) async {
      when(() => repository.listingPhotoUrls(any()))
          .thenAnswer((_) async => {'user-id/sale-id/p0.jpg': 'https://x'});
      await pump(
        tester,
        saleState(sale: _signed),
        page: const ListingPreviewPage(),
        tall: false,
      );
      expect(find.text('Maison de 115 m² à Chaponost'), findsOneWidget);
      expect(find.text('525 000 €'), findsOneWidget);
      expect(find.text('Chaponost'), findsOneWidget);
      expect(find.text('Maison · 115 m² · 5 pièces'), findsOneWidget);
      await tester.screenshot('v11a_preview');
    });

    testWidgets('without photos nor texts', (tester) async {
      when(() => repository.getListingPhotos('sale-id')).thenThrow(Exception());
      await pump(
        tester,
        saleState(
          sale: const Sale(
            id: 'sale-id',
            formula: SaleFormula.essentiel,
            stage: SaleStage.mandateSigned,
          ),
          members: const [],
        ),
        page: const ListingPreviewPage(),
      );
      expect(find.text('Description à rédiger'), findsOneWidget);
    });
  });
}
