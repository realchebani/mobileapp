import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_space/sale/essentiel/essentiel_view.dart';
import 'package:mobileapp/seller_space/sale/expert/expert_view.dart';
import 'package:mobileapp/seller_space/sale/offer_choice/offer_choice_sheet.dart';
import 'package:mobileapp/seller_space/sale/premium/premium_view.dart';
import 'package:mobileapp/seller_space/sale/sale.dart';
import 'package:mobileapp/seller_space/sale/sale_activation_page.dart';
import 'package:mobileapp/seller_space/sale/widgets/sale_sections.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

import '../../helpers/helpers.dart';
import '../fixtures.dart';
import 'sale_helpers.dart';

const _premium = Sale(
  id: 'sale-id',
  propertyId: 'property-id',
  formula: SaleFormula.premium,
  stage: SaleStage.planChosen,
  askingPriceEur: 525000,
);

const _expert = Sale(
  id: 'sale-id',
  propertyId: 'property-id',
  formula: SaleFormula.expert,
  stage: SaleStage.planChosen,
  askingPriceEur: 525000,
);

Sale _signed(Sale sale) => Sale(
  id: sale.id,
  propertyId: sale.propertyId,
  formula: sale.formula,
  stage: SaleStage.mandateSigned,
  askingPriceEur: sale.askingPriceEur,
);

Finder _pad() => find.descendant(
  of: find.byType(SignaturePad),
  matching: find.byType(CustomPaint),
);

void main() {
  setUpAll(loadRealestyFonts);

  late MockGoRouter router;
  late List<Uri> opened;

  setUp(() {
    router = saleRouter();
    opened = [];
  });

  Future<MockSaleCubit> pump(
    WidgetTester tester,
    SaleState state, {
    bool openResult = true,
    ValuationRepository? valuationRepository,
  }) async {
    useTallSurface();
    final cubit = mockSaleCubit(state);
    await tester.pumpSalePage(
      SaleActivationPage(
        openUrl: (url) async {
          opened.add(url);
          return openResult;
        },
      ),
      saleCubit: cubit,
      goRouter: router,
      valuationRepository: valuationRepository,
    );
    return cubit;
  }

  Future<void> sign(WidgetTester tester, String label) async {
    await tester.drag(_pad(), const Offset(80, 20));
    await tester.tap(find.byType(RealestyCheckbox));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  group('V11 · L’Essentiel', () {
    testWidgets('screenshot', (tester) async {
      usePhoneSurface();
      await tester.pumpSalePage(
        const SaleActivationPage(),
        saleCubit: mockSaleCubit(saleState()),
      );
      expect(find.byType(EssentielView), findsOneWidget);
      await tester.screenshot('v11_essentiel');
    });

    testWidgets('continue: refused before the signature', (tester) async {
      await pump(tester, saleState());
      expect(find.text('Formule L’Essentiel'), findsOneWidget);
      await tester.tap(find.text('Activer et préparer mon annonce'));
      await tester.pumpAndSettle();
      expect(find.text('Signez d’abord votre mandat.'), findsOneWidget);
      verifyNever(() => router.push<Object?>(any()));
    });

    testWidgets('continue: the listing once signed', (tester) async {
      await pump(
        tester,
        saleState(sale: _signed(testSale), mandate: testMandate),
      );
      expect(find.text('Mandat signé le 03/10/2026'), findsOneWidget);
      await tester.tap(find.text('Activer et préparer mon annonce'));
      await tester.pumpAndSettle();
      verify(() => router.push<Object?>('/vendeur/ventes/sale-id/annonce'))
          .called(1);
    });

    testWidgets('mandate PDF opens, or tells it could not', (tester) async {
      final state = saleState(sale: _signed(testSale), mandate: testMandate);
      final withUrl = SaleState(
        status: state.status,
        sale: state.sale,
        mandate: state.mandate,
        members: state.members,
        valuations: state.valuations,
        owners: state.owners,
        documentKinds: state.documentKinds,
        mandateUrl: 'https://pdf',
      );
      final cubit = await pump(tester, state);
      when(() => cubit.state).thenReturn(withUrl);
      await tester.tap(find.text('Voir le mandat (PDF)'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://pdf')]);
      await pump(tester, withUrl, openResult: false);
      await tester.tap(find.text('Voir le mandat (PDF)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le mandat n’a pas pu être ouvert. Réessayez.'),
        findsOneWidget,
      );
    });

    testWidgets('identity document missing → vault', (tester) async {
      await pump(tester, saleState(documents: const {}));
      await tester.tap(find.text('Ouvrir mon coffre-fort'));
      verify(() => router.go('/vendeur/coffre')).called(1);
    });

    testWidgets('signature sheet: errors, then signs', (tester) async {
      final cubit = await pump(tester, saleState());
      await tester.tap(find.text('Signer le mandat en ligne'));
      await tester.pumpAndSettle();
      expect(find.text('Signature du mandat'), findsOneWidget);
      expect(find.text('Sophie Durand (vous)'), findsOneWidget);
      expect(find.textContaining('Marc Durand'), findsOneWidget);
      await tester.tap(find.text('Signer'));
      await tester.pumpAndSettle();
      expect(find.text('Signez dans le cadre.'), findsOneWidget);
      expect(find.text('Acceptez les conditions du mandat.'), findsOneWidget);
      await sign(tester, 'Signer');
      verify(
        () => cubit.signMandate(
          signaturePng: any(named: 'signaturePng'),
          accepted: true,
        ),
      ).called(1);
      expect(find.text('Mandat de test signé.'), findsOneWidget);
      expect(find.text('Signature du mandat'), findsNothing);
    });

    testWidgets('signature by typing the name', (tester) async {
      final cubit = await pump(tester, saleState());
      await tester.tap(find.text('Signer le mandat en ligne'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Signer en tapant mon nom'));
      await tester.pump();
      await tester.tap(find.byType(RealestyCheckbox));
      await tester.pump();
      await tester.tap(find.text('Signer'));
      await tester.pump();
      expect(
        find.text('Tapez votre nom (2 caractères au moins).'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), ' Sophie Durand ');
      await tester.tap(find.text('Signer'));
      await tester.pumpAndSettle();
      verify(
        () => cubit.signMandate(typedName: 'Sophie Durand', accepted: true),
      ).called(1);
      await tester.tap(find.text('Signer le mandat en ligne'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Signer en tapant mon nom'));
      await tester.pump();
      await tester.tap(find.text('Signer à la main'));
      await tester.pump();
      expect(find.byType(SignaturePad), findsOneWidget);
    });

    testWidgets('activation steps', (tester) async {
      await pump(
        tester,
        saleState(
          sale: Sale(
            id: 'sale-id',
            propertyId: 'property-id',
            formula: SaleFormula.essentiel,
            stage: SaleStage.mandateSigned,
            askingPriceEur: 525000,
            photosImportedAt: DateTime(2026, 10, 3),
          ),
          mandate: testMandate,
          documents: const {
            DocumentKind.identityDocument,
            DocumentKind.diagnostics,
          },
        ),
      );
      expect(find.text('1 · Mandat'), findsOneWidget);
      expect(find.text('3 · Diagnostics'), findsOneWidget);
      expect(find.text('Exemples de bonnes photos'), findsOneWidget);
    });

    testWidgets('signature refused: the sheet stays', (tester) async {
      await pump(
        tester,
        saleState(
          failure: const SaleFailure(SaleFailureReason.identityDocumentMissing),
        ),
      );
      await tester.tap(find.text('Signer le mandat en ligne'));
      await tester.pumpAndSettle();
      await sign(tester, 'Signer');
      expect(find.text('Signature du mandat'), findsOneWidget);
    });

    testWidgets('photo preferences and services', (tester) async {
      final cubit = await pump(
        tester,
        saleState(
          requests: [
            SaleRequest(
              id: 'r',
              saleId: 'sale-id',
              kind: SaleRequestKind.shootingPhotoVideo,
              status: SaleRequestStatus.scheduled,
              scheduledAt: DateTime(2026, 10, 6, 14),
            ),
          ],
        ),
      );
      await tester.tap(find.byType(RealestySwitch).first);
      await tester.pumpAndSettle();
      verify(() => cubit.updateListing({'ai_retouch_wanted': true})).called(1);
      await tester.tap(find.byType(RealestySwitch).last);
      await tester.pumpAndSettle();
      verify(() => cubit.updateListing({'home_staging_wanted': true}))
          .called(1);
      expect(find.textContaining('Rendez-vous le 06/10/2026'), findsOneWidget);
      await tester.tap(find.text('Ajouter').first);
      await tester.pumpAndSettle();
      verify(
        () => cubit.requestService(
          SaleRequestKind.shootingPhoto,
          diagnostics: any(named: 'diagnostics'),
          preferredSlots: any(named: 'preferredSlots'),
        ),
      ).called(1);
      expect(find.textContaining('Demande envoyée'), findsOneWidget);
      await tester.tap(find.text('Prendre mes photos avec l’assistant'));
      verify(
        () => router.push<Object?>('/vendeur/ventes/sale-id/annonce/photos'),
      ).called(1);
      await tester.tap(find.textContaining('J’ai déjà mes diagnostics'));
      verify(() => router.go('/vendeur/coffre')).called(1);
    });

    testWidgets('a requested service can be cancelled', (tester) async {
      final cubit = await pump(
        tester,
        saleState(
          requests: const [
            SaleRequest(
              id: 'r',
              saleId: 'sale-id',
              kind: SaleRequestKind.diagnostics,
            ),
          ],
          failure: const SaleFailure(SaleFailureReason.requestAlreadyOpen),
        ),
      );
      expect(
        find.text('Demandé · un conseiller vous recontacte'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      verify(() => cubit.cancelRequest(any())).called(1);
      expect(
        find.text('Une demande de ce type est déjà en cours.'),
        findsOneWidget,
      );
    });

    testWidgets('upsell changes the formula', (tester) async {
      final valuations = MockValuationRepository();
      when(() => valuations.getLatestValuation('property-id'))
          .thenAnswer((_) async => testValuation);
      final cubit = await pump(
        tester,
        saleState(),
        valuationRepository: valuations,
      );
      await tester.tap(find.textContaining('Besoin d’être plus accompagné'));
      await tester.pumpAndSettle();
      expect(find.byType(OfferChoiceSheet), findsOneWidget);
      await tester.tap(find.text('Premium'));
      await tester.pump();
      await tester.tap(find.text('Choisir Le Premium'));
      await tester.pumpAndSettle();
      verify(() => cubit.changeFormula(SaleFormula.premium)).called(1);
      expect(find.byType(OfferChoiceSheet), findsNothing);
    });

    testWidgets('pull to refresh', (tester) async {
      final cubit = await pump(tester, saleState());
      usePhoneSurface();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      verify(cubit.refresh).called(1);
    });
  });

  group('V11b · Le Premium', () {
    testWidgets('screenshot', (tester) async {
      usePhoneSurface();
      await tester.pumpSalePage(
        const SaleActivationPage(),
        saleCubit: mockSaleCubit(saleState(sale: _premium)),
      );
      expect(find.byType(PremiumView), findsOneWidget);
      await tester.screenshot('v11b_premium');
    });

    testWidgets('callback, shooting with slots, diagnostics', (tester) async {
      useTallSurface(4000);
      final cubit = mockSaleCubit(
        saleState(
          sale: _premium,
          members: const [
            Property(
              id: 'property-id',
              ownerId: 'user-id',
              status: PropertyStatus.certified,
              propertyType: PropertyType.house,
              constructionYear: 1930,
              heatingSystems: [HeatingSystem.gas],
            ),
          ],
        ),
      );
      await tester.pumpSalePage(
        PremiumView(
          openUrl: (_) async => true,
          now: () => DateTime(2026, 10, 2),
        ),
        saleCubit: cubit,
        goRouter: router,
      );
      expect(
        find.textContaining('construction 1930, chauffage au gaz'),
        findsOneWidget,
      );
      expect(
        find.text('Aucun diagnostic trouvé dans votre dossier.'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Photo + vidéo'));
      await tester.pump();
      final slots = find.byWidgetPredicate(
        (widget) => widget is RealestyChoiceChip && widget.label.contains(' h'),
      );
      expect(slots, findsNWidgets(6));
      for (var i = 0; i < 4; i++) {
        await tester.tap(slots.at(i));
        await tester.pump();
      }
      // The fourth one is not taken; a second tap removes the first.
      await tester.tap(slots.at(0));
      await tester.pump();
      await tester.tap(find.text('Termites'));
      await tester.tap(find.text('DPE'));
      await tester.pump();
      final add = find.text('Ajouter');
      await tester.tap(add.at(0));
      await tester.pumpAndSettle();
      verify(
        () => cubit.requestService(
          SaleRequestKind.premiumSetup,
          diagnostics: any(named: 'diagnostics'),
          preferredSlots: any(named: 'preferredSlots'),
        ),
      ).called(1);
      await tester.tap(add.at(1));
      await tester.pumpAndSettle();
      verify(
        () => cubit.requestService(
          SaleRequestKind.shootingPhotoVideo,
          diagnostics: any(named: 'diagnostics'),
          preferredSlots: [
            DateTime(2026, 10, 5, 14),
            DateTime(2026, 10, 6, 10),
          ],
        ),
      ).called(1);
      await tester.tap(add.at(2));
      await tester.pumpAndSettle();
      verify(
        () => cubit.requestService(
          SaleRequestKind.diagnostics,
          diagnostics: [
            Diagnostic.electricity,
            Diagnostic.gas,
            Diagnostic.asbestos,
            Diagnostic.lead,
            Diagnostic.termites,
            Diagnostic.risks,
          ],
          preferredSlots: any(named: 'preferredSlots'),
        ),
      ).called(1);
      await tester.tap(find.textContaining('J’ai déjà mes diagnostics'));
      verify(() => router.go('/vendeur/coffre')).called(1);
      await tester.tap(find.text('Continuer vers mon annonce'));
      await tester.pumpAndSettle();
      verifyNever(() => router.push<Object?>(any()));
    });

    testWidgets('open requests; signed; unknown year', (tester) async {
      useTallSurface(4000);
      final cubit = mockSaleCubit(
        saleState(
          sale: _signed(_premium),
          mandate: testMandate,
          documents: const {
            DocumentKind.identityDocument,
            DocumentKind.diagnostics,
          },
          members: const [
            Property(
              id: 'property-id',
              ownerId: 'user-id',
              status: PropertyStatus.certified,
              propertyType: PropertyType.house,
            ),
          ],
          requests: const [
            SaleRequest(
              id: 'a',
              saleId: 'sale-id',
              kind: SaleRequestKind.shootingPhoto,
            ),
            SaleRequest(
              id: 'b',
              saleId: 'sale-id',
              kind: SaleRequestKind.diagnostics,
            ),
          ],
        ),
      );
      await tester.pumpSalePage(
        PremiumView(openUrl: (_) async => true),
        saleCubit: cubit,
        goRouter: router,
      );
      expect(
        find.textContaining('année de construction inconnue'),
        findsOneWidget,
      );
      expect(find.text('Changer de formule'), findsNothing);
      await tester.tap(find.text('DPE'));
      await tester.tap(find.text('Continuer vers mon annonce'));
      await tester.pumpAndSettle();
      verify(() => router.push<Object?>('/vendeur/ventes/sale-id/annonce'))
          .called(1);
    });

    testWidgets('change of formula while not signed', (tester) async {
      final valuations = MockValuationRepository();
      when(() => valuations.getLatestValuation(any())).thenThrow(Exception());
      final cubit = await pump(
        tester,
        saleState(
          sale: _premium,
          failure: const SaleFailure(SaleFailureReason.mandateAlreadySigned),
        ),
        valuationRepository: valuations,
      );
      await tester.tap(find.text('Changer de formule'));
      await tester.pumpAndSettle();
      expect(find.text('Garder cette formule'), findsOneWidget);
      await tester.tap(find.text('3\u00a0%'));
      await tester.pump();
      await tester.tap(find.text('Choisir L’Expert'));
      await tester.pumpAndSettle();
      verify(() => cubit.changeFormula(SaleFormula.expert)).called(1);
      expect(find.textContaining('Le mandat est signé'), findsOneWidget);
      await tester.tap(find.text('Premium'));
      await tester.pump();
      await tester.tap(find.text('Garder cette formule'));
      await tester.pumpAndSettle();
      expect(find.byType(OfferChoiceSheet), findsNothing);
    });
  });

  testWidgets('V11b and V11c: pull to refresh; V11b continue', (tester) async {
    for (final sale in [_premium, _expert]) {
      final cubit = await pump(tester, saleState(sale: sale));
      usePhoneSurface();
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      verify(cubit.refresh).called(1);
    }
    await pump(tester, saleState(sale: _premium));
    usePhoneSurface();
    await tester.pump();
    await tester.tap(find.text('Continuer vers mon annonce'));
    await tester.pumpAndSettle();
    expect(find.text('Signez d’abord votre mandat.'), findsOneWidget);
  });

  testWidgets('formula summary without price (L’Expert)', (tester) async {
    await tester.pumpSalePage(
      const SingleChildScrollView(child: FormulaSummaryCard()),
      saleCubit: mockSaleCubit(
        const SaleState(
          status: SaleLoadStatus.ready,
          sale: Sale(
            id: 'sale-id',
            formula: SaleFormula.expert,
            stage: SaleStage.planChosen,
          ),
        ),
      ),
    );
    expect(find.text('3\u00a0% au succès'), findsOneWidget);
    expect(find.text('Visites menées par l’agent'), findsOneWidget);
  });

  group('V11c · L’Expert', () {
    testWidgets('screenshot', (tester) async {
      usePhoneSurface();
      await tester.pumpSalePage(
        const SaleActivationPage(),
        saleCubit: mockSaleCubit(saleState(sale: _expert, verified: true)),
      );
      expect(find.byType(ExpertView), findsOneWidget);
      await tester.screenshot('v11c_expert');
    });

    testWidgets('identity not verified: signature disabled', (tester) async {
      await pump(tester, saleState(sale: _expert));
      expect(
        find.text('En cours de vérification par notre équipe'),
        findsOneWidget,
      );
      final button = tester.widget<RealestyButton>(
        find.widgetWithText(RealestyButton, 'Signer le mandat'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('identity document missing', (tester) async {
      await pump(tester, saleState(sale: _expert, documents: const {}));
      expect(find.text('Pièce d’identité à ajouter'), findsOneWidget);
    });

    testWidgets('verified: signs inline', (tester) async {
      final cubit = await pump(
        tester,
        saleState(sale: _expert, verified: true),
      );
      await sign(tester, 'Signer le mandat');
      verify(
        () => cubit.signMandate(
          signaturePng: any(named: 'signaturePng'),
          accepted: true,
        ),
      ).called(1);
    });

    testWidgets('signed: an agent calls', (tester) async {
      await pump(
        tester,
        saleState(sale: _signed(_expert), mandate: testMandate, verified: true),
      );
      expect(find.text('Mandat signé le 03/10/2026'), findsWidgets);
      await tester.tap(find.text('Retour à mes biens'));
      verify(() => router.go('/vendeur')).called(1);
    });
  });
}
