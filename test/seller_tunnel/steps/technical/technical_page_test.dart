import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/models/technical_options.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/widgets/technical_question.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = '\u00a0';

const _filled = Property(
  id: 'property-id',
  ownerId: 'user-id',
  propertyType: PropertyType.house,
  constructionYear: 1998,
  orientation: 'sud',
  livingAreaM2: 115,
  livingRoomAreaM2: 38.5,
  roomsCount: 5,
  bedroomsCount: 3,
  levels: PropertyLevels.oneUpperFloor,
  wallMaterial: WallMaterial.concreteBlock,
  adjacency: Adjacency.detached,
  roofType: 'tuiles',
  roofYear: 2016,
  heatingSystems: [HeatingSystem.heatPump, HeatingSystem.pellets],
  heatPumpType: 'air_eau',
  heatPumpYear: 2021,
  sanitation: Sanitation.mainsSewer,
  outdoorEquipment: [OutdoorEquipment.pool, OutdoorEquipment.garage],
  poolType: 'enterree_liner',
  poolLengthM: 8,
  poolWidthM: 4,
  provenance: {
    'heat_pump_year': 'document',
    'living_area_m2': 'external',
    'wall_material': {'source': 'expert'},
    'orientation': 'ai',
    'heating_systems': 'external',
  },
);

SellerTunnelState _loaded(Property property) =>
    SellerTunnelState(status: SellerTunnelStatus.success, property: property);

/// The text input of the field labelled [label].
Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(TextField),
);

bool _chipSelected(WidgetTester tester, String label) => tester
    .widget<RealestyChoiceChip>(find.widgetWithText(RealestyChoiceChip, label))
    .selected;

void main() {
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
    final cubit = mockSellerTunnelCubit(state ?? _loaded(_filled));
    await tester.pumpTunnelPage(
      const TechnicalPage(),
      sellerTunnelCubit: cubit,
      goRouter: goRouter,
    );
    return cubit;
  }

  Future<void> pick(WidgetTester tester, String select, String option) async {
    await tester.tap(find.text(select).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  /// Scrolls [finder] into view and taps it.
  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  group(TechnicalPage, () {
    testWidgets('shows the saved answers and their provenance', (tester) async {
      await pump(tester);

      expect(find.text('Étape 4 · Technique'), findsOneWidget);
      expect(find.text('Écran'), findsOneWidget);
      expect(find.text('Carte d’identité'), findsOneWidget);
      expect(find.text('1998'), findsOneWidget);
      expect(find.text('Sud'), findsOneWidget);
      expect(find.text('115'), findsOneWidget);
      expect(find.text('38,5'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Tuiles'), findsOneWidget);
      expect(find.text('Air / eau'), findsOneWidget);
      expect(find.text('Enterrée · liner'), findsOneWidget);
      expect(find.text('8 × 4'), findsWidgets);
      expect(_chipSelected(tester, 'Parpaing'), isTrue);
      expect(_chipSelected(tester, 'Indépendant'), isTrue);
      expect(_chipSelected(tester, 'Pompe à chaleur'), isTrue);
      expect(_chipSelected(tester, 'Poêle à granulés'), isTrue);
      expect(_chipSelected(tester, 'Gaz'), isFalse);
      expect(_chipSelected(tester, 'Tout-à-l’égout'), isTrue);
      expect(_chipSelected(tester, 'Piscine'), isTrue);
      expect(_chipSelected(tester, 'Terrasse'), isFalse);

      expect(find.byType(TechnicalProvenanceTag), findsNWidgets(7));
      expect(find.text('Déclaré'), findsNWidgets(2));
      expect(find.text('Extrait d’un document'), findsOneWidget);
      expect(find.text('Source externe'), findsNWidgets(2));
      expect(find.text('Vérifié expert'), findsOneWidget);
      expect(find.text('Estimé IA'), findsOneWidget);
      expect(
        find.text(
          'Chaque information indique sa provenance. Une facture importée '
          'transforme «${_nbsp}Déclaré$_nbsp» en '
          '«${_nbsp}Extrait d’un document$_nbsp».',
        ),
        findsOneWidget,
      );
      // The voice hint is hidden with the microphone.
      expect(find.text('Répondez à la voix ou à l’écran'), findsNothing);
    });

    testWidgets('an edited answer becomes declared', (tester) async {
      await pump(tester);

      await tester.enterText(_field('Année PAC'), '2022');
      await tester.pump();
      expect(find.text('Extrait d’un document'), findsNothing);
      expect(find.text('Déclaré'), findsNWidgets(3));
    });

    testWidgets('clears an optional select', (tester) async {
      final cubit = await pump(tester);

      await pick(tester, 'Tuiles', 'Non précisé');
      expect(find.text('Tuiles'), findsNothing);
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      final patch =
          verify(
                () => cubit.saveAndContinue(
                  SellerTunnelStep.technical,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch[PropertyColumns.roofType], isNull);
      expect(patch.containsKey(PropertyColumns.provenance), isFalse);
    });

    testWidgets('lines up paired fields when a label wraps', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 3000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpTunnelPage(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: const TechnicalPage(),
          ),
        ),
        sellerTunnelCubit: mockSellerTunnelCubit(_loaded(_filled)),
      );

      final field = tester.getTopLeft(_field('Année de construction')).dy;
      final box = tester
          .getTopLeft(
            find
                .ancestor(
                  of: find.text('Sud'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .dy;
      // The construction year label wraps, the exposure one does not.
      expect(
        tester.getSize(find.text('Année de construction')).height,
        greaterThan(tester.getSize(find.text('Exposition')).height),
      );
      expect(box, closeTo(field, 1));
    });

    testWidgets('goes back to the context', (tester) async {
      final goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      await pump(tester, goRouter: goRouter);

      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go(auditRoute(SellerTunnelStep.context))).called(1);
    });

    testWidgets('hides back while saving', (tester) async {
      await pump(
        tester,
        state: _loaded(_filled)
            .copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
      );
      expect(find.bySemanticsLabel('Retour'), findsNothing);
    });

    testWidgets('saves the answers and continues', (tester) async {
      final cubit = await pump(tester);

      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();

      final patch =
          verify(
                () => cubit.saveAndContinue(
                  SellerTunnelStep.technical,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch[PropertyColumns.constructionYear], 1998);
      expect(patch[PropertyColumns.poolLengthM], 8.0);
      expect(patch.containsKey(PropertyColumns.provenance), isFalse);
    });

    testWidgets('edits every answer', (tester) async {
      final cubit = await pump(
        tester,
        state: _loaded(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.house,
          ),
        ),
      );

      await tester.enterText(_field('Année de construction'), '1975');
      await tester.enterText(_field('Surface habitable'), '120.5');
      await tester.enterText(_field('Surface séjour'), '40');
      await pick(tester, 'Choisir', 'Traversant');
      await tester.tap(find.bySemanticsLabel('Ajouter Pièces'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Ajouter Pièces'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Ajouter Chambres'));
      await tester.tap(find.text('Plain-pied'));
      await tester.tap(find.text('Brique'));
      await tester.tap(find.text('2 côtés'));
      await pick(tester, 'Choisir', 'Ardoises');
      await tester.enterText(_field('Année toiture'), '2010');
      await tester.tap(find.text('Électrique'));
      await tester.tap(find.text('Pompe à chaleur'));
      await tester.pump();
      await pick(tester, 'Choisir', 'Géothermique');
      await tester.enterText(_field('Année PAC'), '2020');
      await tester.tap(find.text('Fosse septique'));
      await tester.tap(find.text('Piscine'));
      await tester.tap(find.text('Abri de jardin'));
      await tester.pump();
      await pick(tester, 'Choisir', 'Hors-sol');
      await tester.enterText(_field('Dimensions'), '6x3,5');
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();

      final patch =
          verify(
                () => cubit.saveAndContinue(
                  SellerTunnelStep.technical,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch, containsPair(PropertyColumns.constructionYear, 1975));
      expect(patch, containsPair(PropertyColumns.livingAreaM2, 120.5));
      expect(patch, containsPair(PropertyColumns.livingRoomAreaM2, 40.0));
      expect(
        patch,
        containsPair(PropertyColumns.orientation, Exposure.dualAspect),
      );
      expect(patch, containsPair(PropertyColumns.roomsCount, 3));
      expect(patch, containsPair(PropertyColumns.bedroomsCount, 1));
      expect(
        patch,
        containsPair(PropertyColumns.levels, PropertyLevels.singleStorey),
      );
      expect(
        patch,
        containsPair(PropertyColumns.wallMaterial, WallMaterial.brick),
      );
      expect(
        patch,
        containsPair(PropertyColumns.adjacency, Adjacency.twoSides),
      );
      expect(patch, containsPair(PropertyColumns.roofType, RoofType.slate));
      expect(patch, containsPair(PropertyColumns.roofYear, 2010));
      expect(
        patch,
        containsPair(PropertyColumns.heatingSystems, [
          HeatingSystem.electricity,
          HeatingSystem.heatPump,
        ]),
      );
      expect(
        patch,
        containsPair(PropertyColumns.heatPumpType, HeatPumpType.geothermal),
      );
      expect(patch, containsPair(PropertyColumns.heatPumpYear, 2020));
      expect(
        patch,
        containsPair(PropertyColumns.sanitation, Sanitation.septicTank),
      );
      expect(
        patch,
        containsPair(PropertyColumns.outdoorEquipment, [
          OutdoorEquipment.pool,
          OutdoorEquipment.gardenShed,
        ]),
      );
      expect(
        patch,
        containsPair(PropertyColumns.poolType, PoolType.aboveGround),
      );
      expect(patch, containsPair(PropertyColumns.poolLengthM, 6.0));
      expect(patch, containsPair(PropertyColumns.poolWidthM, 3.5));
      expect(
        (patch[PropertyColumns.provenance]! as Map)[PropertyColumns.roofYear],
        'declared',
      );
    });

    testWidgets('shows the errors and reveals the first one', (tester) async {
      final cubit = await pump(
        tester,
        height: 844,
        state: _loaded(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.house,
          ),
        ),
      );

      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(find.text('Indiquez l’année de construction'), findsOneWidget);
      expect(find.text('Indiquez la surface habitable'), findsOneWidget);
      expect(find.text('Indiquez le nombre de niveaux'), findsOneWidget);
      verifyNever(() => cubit.saveAndContinue(any(), any()));

      // Reveals the heating once the identity card is answered.
      await tester.enterText(_field('Année de construction'), '1998');
      await tester.enterText(_field('Surface habitable'), '100');
      await show(tester, find.text('R+1'));
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choisissez au moins un système de chauffage').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Carte d’identité').hitTestable(), findsNothing);

      // Then the other invalid answers, in order.
      await show(tester, find.text('Gaz'));
      await show(tester, find.text('Piscine'));
      await tester.pump();
      await tester.ensureVisible(_field('Dimensions'));
      await tester.enterText(_field('Dimensions'), '8');
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Format attendu$_nbsp: longueur × largeur, ex. 8 × 4'),
        findsOneWidget,
      );
      for (final (field, value) in [
        ('Année toiture', '1990'),
        ('Surface séjour', '200'),
      ]) {
        await tester.ensureVisible(_field(field));
        await tester.enterText(_field(field), value);
        await tester.tap(find.text('Enregistrer et continuer'));
        await tester.pumpAndSettle();
        expect(_field(field).hitTestable(), findsOneWidget);
      }
      expect(
        find.text('Indiquez une année entre 1998 et ${DateTime.now().year}'),
        findsOneWidget,
      );
      expect(
        find.text('Le séjour ne peut pas dépasser la surface habitable'),
        findsOneWidget,
      );
    });

    testWidgets('reveals the levels and the heat pump', (tester) async {
      await pump(
        tester,
        height: 844,
        state: _loaded(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.house,
            constructionYear: 1998,
            livingAreaM2: 100,
            heatingSystems: [HeatingSystem.heatPump],
            heatPumpYear: 1850,
          ),
        ),
      );

      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indiquez le nombre de niveaux').hitTestable(),
        findsOneWidget,
      );
      await show(tester, find.text('R+1'));
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(_field('Année PAC').hitTestable(), findsOneWidget);
    });

    testWidgets('checks the ranges', (tester) async {
      await pump(tester);

      await tester.enterText(_field('Année de construction'), '1500');
      await tester.enterText(_field('Surface habitable'), '3');
      await tester.enterText(_field('Surface séjour'), '0');
      await tester.enterText(_field('Année PAC'), '1850');
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();

      final year = DateTime.now().year;
      expect(
        find.text('Indiquez une année entre 1600 et $year'),
        findsOneWidget,
      );
      expect(
        find.text('Indiquez une année entre 1900 et $year'),
        findsOneWidget,
      );
      expect(
        find.text('Indiquez une surface entre 5 et 2${_nbsp}000${_nbsp}m²'),
        findsOneWidget,
      );
      expect(
        find.text('Indiquez une surface entre 1 et 2${_nbsp}000${_nbsp}m²'),
        findsOneWidget,
      );
      await tester.enterText(_field('Année de construction'), '1998');
      await tester.enterText(_field('Année toiture'), '1990');
      await tester.pump();
      expect(
        find.text('Indiquez une année entre 1998 et $year'),
        findsOneWidget,
      );
    });

    testWidgets('hides the hidden questions', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Gaz'));
      await tester.pump();
      // Several systems: the heat pump stays selected with its details.
      expect(_chipSelected(tester, 'Gaz'), isTrue);
      expect(_chipSelected(tester, 'Pompe à chaleur'), isTrue);
      expect(find.text('Type de PAC'), findsOneWidget);
      await tester.tap(find.text('Pompe à chaleur'));
      await tester.tap(find.text('Piscine'));
      await tester.pump();
      expect(find.text('Type de PAC'), findsNothing);
      expect(find.text('Type de piscine'), findsNothing);
    });

    testWidgets('asks only the questions of an apartment', (tester) async {
      await pump(
        tester,
        state: _loaded(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.apartment,
          ),
        ),
      );

      expect(find.text('Carte d’identité'), findsOneWidget);
      expect(find.text('Matériaux des murs'), findsOneWidget);
      expect(find.text('Niveaux'), findsNothing);
      expect(find.text('Mitoyenneté'), findsNothing);
      expect(find.text('Toiture'), findsNothing);
      expect(
        find.text('Systèmes de chauffage (plusieurs choix possibles)'),
        findsOneWidget,
      );
    });

    testWidgets('makes the heating optional for another property', (
      tester,
    ) async {
      final cubit = await pump(
        tester,
        state: _loaded(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.other,
            constructionYear: 1998,
            livingAreaM2: 100,
          ),
        ),
      );

      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      expect(
        find.text('Choisissez au moins un système de chauffage'),
        findsNothing,
      );
      final patch =
          verify(
                () => cubit.saveAndContinue(
                  SellerTunnelStep.technical,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch[PropertyColumns.heatingSystems], isEmpty);
    });

    testWidgets('asks only the questions of a plot of land', (tester) async {
      final cubit = await pump(
        tester,
        state: _loaded(
          const Property(
            id: 'property-id',
            ownerId: 'user-id',
            propertyType: PropertyType.land,
          ),
        ),
      );

      expect(find.text('Carte d’identité'), findsNothing);
      expect(find.text('Gros œuvre'), findsNothing);
      expect(
        find.text('Systèmes de chauffage (plusieurs choix possibles)'),
        findsNothing,
      );
      expect(find.text('Assainissement'), findsOneWidget);
      expect(find.text('Équipements extérieurs'), findsOneWidget);

      await tester.tap(find.text('Puits perdu'));
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      final patch =
          verify(
                () => cubit.saveAndContinue(
                  SellerTunnelStep.technical,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(patch[PropertyColumns.sanitation], Sanitation.soakaway);
      expect(patch[PropertyColumns.constructionYear], isNull);
    });

    testWidgets('disables the answers while saving', (tester) async {
      await pump(
        tester,
        state: _loaded(_filled)
            .copyWith(saveStatus: SellerTunnelSaveStatus.inProgress),
      );

      expect(
        tester
            .widget<RealestyTextField>(find.byType(RealestyTextField).first)
            .enabled,
        isFalse,
      );
      for (final select in tester.widgetList<RealestySelect<dynamic>>(
        find.byWidgetPredicate((w) => w is RealestySelect),
      )) {
        expect(select.onChanged, isNull);
      }
      expect(
        tester
            .widget<RealestyStepper>(find.byType(RealestyStepper).first)
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<RealestyChoiceChip>(find.byType(RealestyChoiceChip).first)
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<RealestySegmentedControl<PropertyLevels?>>(
              find.byType(RealestySegmentedControl<PropertyLevels?>),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<RealestyButton>(find.byType(RealestyButton)).isLoading,
        isTrue,
      );
    });
  });
}
