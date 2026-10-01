import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/context_question.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/widgets/previous_estimate_card.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

const _estimate = PreviousEstimate(
  id: 'e1',
  propertyId: 'property-id',
  priceEur: 510000,
);

const _answered = SellerTunnelState(
  status: SellerTunnelStatus.success,
  property: Property(
    id: 'property-id',
    ownerId: 'user-id',
    propertyType: PropertyType.house,
    purchaseYear: 2012,
    purchasePriceEur: 320000,
    selfBuilt: false,
    saleReason: SaleReason.moreSpace,
    previouslyEstimated: true,
  ),
  previousEstimates: [_estimate],
);

/// The text input of the field labelled [label].
Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(TextField),
);

void main() {
  late MockPropertyRepository repository;

  setUpAll(() => registerFallbackValue(_estimate));

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.savePreviousEstimate(any()))
        .thenAnswer((invocation) async {
          final estimate =
              invocation.positionalArguments.single as PreviousEstimate;
          return PreviousEstimate(
            id: estimate.id ?? 'new',
            propertyId: estimate.propertyId,
            priceEur: estimate.priceEur,
            estimatedMonth: estimate.estimatedMonth,
            agencyName: estimate.agencyName,
          );
        });
    when(() => repository.deletePreviousEstimate(any()))
        .thenAnswer((_) async {});
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    SellerTunnelState state = const SellerTunnelState(
      status: SellerTunnelStatus.success,
      property: testProperty,
    ),
    double height = 2000,
    MockGoRouter? goRouter,
  }) async {
    final view = tester.view
      ..physicalSize = Size(390, height)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
    final cubit = mockSellerTunnelCubit(state);
    await tester.pumpTunnelPage(
      const PropertyContextPage(),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
      goRouter: goRouter,
    );
    return cubit;
  }

  group(PropertyContextPage, () {
    testWidgets('shows the saved answers', (tester) async {
      await pump(tester, state: _answered);

      expect(find.text('Étape 3 · Contexte'), findsOneWidget);
      expect(
        find.text(
          'Depuis quelle année êtes-vous propriétaire$_nbsp? Et de quel '
          'type de bien s’agit-il$_nbsp? J’adapterai mes questions.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SelectableCard>(
              find.widgetWithText(SelectableCard, 'Maison'),
            )
            .selected,
        isTrue,
      );
      expect(find.text('Immeuble, local, garage…'), findsOneWidget);
      expect(find.text('2012'), findsOneWidget);
      expect(find.text('320${_nbsp}000'), findsOneWidget);
      expect(find.text('Facultatif'), findsOneWidget);
      expect(
        tester
            .widget<RealestyChoiceChip>(
              find.widgetWithText(RealestyChoiceChip, 'Agrandissement'),
            )
            .selected,
        isTrue,
      );
      expect(find.byType(PreviousEstimateCard), findsOneWidget);
      expect(find.text('ESTIMATION PRÉCÉDENTE'), findsOneWidget);
      expect(find.text('510${_nbsp}000'), findsOneWidget);
      expect(find.text('Ajouter une autre agence'), findsOneWidget);
      expect(
        find.text('Les questions facultatives peuvent être passées'),
        findsOneWidget,
      );
    });

    testWidgets('goes back to the cadastre', (tester) async {
      final goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      await pump(tester, goRouter: goRouter);

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(AppRoutes.sellerLocation)).called(1);
    });

    testWidgets('shows the errors and reveals the first one', (tester) async {
      final cubit = await pump(tester, height: 844);

      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(find.text('Choisissez le type de bien'), findsOneWidget);
      expect(find.text('Indiquez l’année d’achat'), findsOneWidget);
      expect(
        find.text('Indiquez si vous avez construit ce bien'),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));

      // Reveals the year once the type is chosen.
      await tester.tap(find.text('Maison'));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Historique'.toUpperCase()), findsOneWidget);
      expect(find.text('Indiquez l’année d’achat'), findsOneWidget);
    });

    testWidgets('checks the ranges of the year and the amounts', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('Maison'));
      await tester.enterText(_field('Année d’achat'), '1850');
      await tester.enterText(_field('Prix d’achat'), '12');
      await tester.tap(find.text('Oui').first);
      await tester.tap(find.text('Oui').last);
      await tester.pump();
      await tester.enterText(_field('Prix estimé'), '5');
      await tester.enterText(_field('Date'), '132020');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Indiquez une année entre 1900 et ${DateTime.now().year}'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Indiquez un montant entre 1${_nbsp}000 et '
          '100${_nbsp}000${_nbsp}000$_nbsp€',
        ),
        findsNWidgets(2),
      );
      expect(find.text('Format attendu$_nbsp: mm/aaaa'), findsOneWidget);

      await tester.enterText(_field('Date'), '01/2999');
      await tester.pump();
      expect(find.text('Indiquez une date passée'), findsOneWidget);

      await tester.enterText(_field('Date'), '01/1850');
      await tester.pump();
      expect(find.text('Indiquez une date à partir de 1900'), findsOneWidget);
    });

    testWidgets('puts the estimate fields on their own lines with large '
        'text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, state: _answered);

      expect(
        tester.getTopLeft(_field('Date')).dy,
        greaterThan(tester.getBottomLeft(_field('Prix estimé')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('puts the estimate fields side by side', (tester) async {
      await pump(tester, state: _answered);

      expect(
        tester.getTopLeft(_field('Date')).dy,
        tester.getTopLeft(_field('Prix estimé')).dy,
      );
    });

    testWidgets('reveals "Construit par vous ?" and the estimates', (
      tester,
    ) async {
      await pump(tester, height: 844);

      await tester.tap(find.text('Appartement'));
      await tester.enterText(_field('Année d’achat'), '2012');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indiquez si vous avez construit ce bien'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Non').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non').first);
      await tester.ensureVisible(find.text('Oui').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oui').last);
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Indiquez le prix estimé'), findsOneWidget);
      expect(
        find.text('Indiquez si vous avez construit ce bien'),
        findsNothing,
      );
    });

    testWidgets('asks to specify "Autre" and skips "Construit par vous ?" '
        'for a plot of land', (tester) async {
      await pump(tester);

      expect(
        tester
            .widget<SelectableCard>(
              find.widgetWithText(SelectableCard, 'Autre').first,
            )
            .icon,
        RealestyIcons.grid,
      );
      await tester.tap(find.text('Autre').first);
      await tester.pump();
      await tester.enterText(_field('Précisez le type de bien'), 'Garage');
      expect(find.text('Construit par vous$_nbsp?'), findsOneWidget);

      await tester.tap(find.text('Terrain'));
      await tester.pump();
      expect(find.text('Précisez le type de bien'), findsNothing);
      expect(find.text('Construit par vous$_nbsp?'), findsNothing);
      expect(find.byType(ContextQuestion), findsNWidgets(2));
    });

    testWidgets('saves the answers and the estimates, then continues', (
      tester,
    ) async {
      final cubit = await pump(tester);

      await tester.tap(find.text('Maison'));
      await tester.enterText(_field('Année d’achat'), '2012');
      await tester.enterText(_field('Prix d’achat'), '320000');
      await tester.tap(find.text('Non').first);
      await tester.tap(find.text('Séparation'));
      await tester.tap(find.text('Oui').last);
      await tester.pump();
      await tester.enterText(_field('Prix estimé'), '510000');
      await tester.enterText(_field('Date'), '052024');
      await tester.enterText(_field('Agence'), 'Agence du Port');

      await tester.tap(find.text('Ajouter une autre agence'));
      await tester.pump();
      expect(find.text('ESTIMATION PRÉCÉDENTE 1'), findsOneWidget);
      expect(find.text('ESTIMATION PRÉCÉDENTE 2'), findsOneWidget);
      await tester.tap(
        find.bySemanticsLabel('Supprimer Estimation précédente 2'),
      );
      await tester.pump();
      expect(find.byType(PreviousEstimateCard), findsOneWidget);

      await tester.tap(find.text('Continuer'));
      await tester.pump();

      final saved = PreviousEstimate(
        id: 'new',
        propertyId: 'property-id',
        priceEur: 510000,
        estimatedMonth: DateTime(2024, 5),
        agencyName: 'Agence du Port',
      );
      verify(() => cubit.updateChildren(previousEstimates: [saved])).called(1);
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.context, {
          PropertyColumns.propertyType: PropertyType.house,
          PropertyColumns.propertyTypeOther: null,
          PropertyColumns.purchaseYear: 2012,
          PropertyColumns.purchasePriceEur: 320000,
          PropertyColumns.selfBuilt: false,
          PropertyColumns.saleReason: SaleReason.separation,
          PropertyColumns.previouslyEstimated: true,
        }),
      ).called(1);
    });

    testWidgets('shows an error when the estimates cannot be saved', (
      tester,
    ) async {
      when(() => repository.deletePreviousEstimate(any()))
          .thenThrow(Exception('offline'));
      final cubit = await pump(tester, state: _answered);

      await tester.tap(find.text('Non').last);
      await tester.tap(find.text('Continuer'));
      await tester.pump();

      expect(
        find.text(
          'L’enregistrement a échoué. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));
    });

    testWidgets('shows the tunnel save in progress', (tester) async {
      await pump(
        tester,
        state: _answered.copyWith(
          saveStatus: SellerTunnelSaveStatus.inProgress,
        ),
      );

      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
    });
  });
}
