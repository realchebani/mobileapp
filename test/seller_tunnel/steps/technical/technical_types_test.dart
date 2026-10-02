import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/cubit/technical_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(TextField),
);

void main() {
  final today = DateTime(2026, 10);

  setUpAll(() {
    registerFallbackValue(SellerTunnelStep.technical);
    registerFallbackValue(<String, Object?>{});
  });

  Property property(PropertyType type) =>
      Property(id: 'p', ownerId: 'u', propertyType: type);

  group('TechnicalState by type', () {
    test('a garage: surface utile, level and equipment', () {
      final cubit = TechnicalCubit(
        property: const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.parking,
          usableAreaM2: 14.5,
          parkingLevel: ParkingLevel.basement,
          parkingFeatures: [ParkingFeature.electricity],
          livingAreaM2: 90,
        ),
        today: today,
      );
      expect(cubit.state.usableArea, '14,5');
      cubit
        ..parkingLevelToggled(ParkingLevel.basement)
        ..parkingLevelToggled(ParkingLevel.outdoor)
        ..parkingFeatureToggled(ParkingFeature.electricity)
        ..parkingFeatureToggled(ParkingFeature.chargingPoint)
        ..parkingFeatureToggled(ParkingFeature.motorizedDoor)
        ..usableAreaChanged('12');
      final state = cubit.state;
      expect(state.isValid, isTrue);
      expect(state.values, {
        PropertyColumns.usableAreaM2: 12.0,
        PropertyColumns.parkingLevel: ParkingLevel.outdoor,
        PropertyColumns.parkingFeatures: [
          ParkingFeature.motorizedDoor,
          ParkingFeature.chargingPoint,
        ],
      });
      // The living area of the former type is kept (hidden).
      expect(state.values.containsKey(PropertyColumns.livingAreaM2), isFalse);
      expect(state.usableAreaError, isNull);
      expect(
        state.copyWith(usableArea: '0').usableAreaError,
        TechnicalError.areaRange,
      );
    });

    test('an outbuilding keeps only electricity and water', () {
      final state = TechnicalState(
        property: property(PropertyType.outbuilding),
        today: today,
        parkingFeatures: const [
          ParkingFeature.water,
          ParkingFeature.chargingPoint,
        ],
      );
      expect(state.values[PropertyColumns.parkingFeatures], [
        ParkingFeature.water,
      ]);
      expect(state.constructionYearError, isNull);
      expect(
        state.copyWith(constructionYear: '3000').constructionYearError,
        TechnicalError.yearRange,
      );
    });

    test('a commercial premises requires its surface', () {
      final state = TechnicalState(
        property: property(PropertyType.commercial),
        today: today,
      );
      expect(state.usableAreaError, TechnicalError.required);
      expect(state.isValid, isFalse);
      expect(state.requiresHeating, isFalse);
    });

    test('a building asks its year, walls, roof, heating and sanitation', () {
      final state = TechnicalState(
        property: property(PropertyType.building),
        today: today,
        constructionYear: '1930',
        roofYear: '1920',
      );
      expect(state.roofYearError, TechnicalError.yearRange);
      expect(
        state.values.keys,
        containsAll([
          PropertyColumns.constructionYear,
          PropertyColumns.wallMaterial,
          PropertyColumns.roofType,
          PropertyColumns.heatingSystems,
          PropertyColumns.sanitation,
        ]),
      );
      expect(state.values.containsKey(PropertyColumns.levels), isFalse);
    });
  });

  group('TechnicalPage by type', () {
    Future<MockSellerTunnelCubit> pump(
      WidgetTester tester,
      PropertyType type,
    ) async {
      final view = tester.view
        ..physicalSize = const Size(390, 3000)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      final cubit = mockSellerTunnelCubit(
        SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: property(type),
        ),
      );
      await tester.pumpTunnelPage(
        const TechnicalPage(),
        sellerTunnelCubit: cubit,
      );
      return cubit;
    }

    testWidgets('a garage', (tester) async {
      final cubit = await pump(tester, PropertyType.parking);
      expect(find.text('L’emplacement'), findsOneWidget);
      expect(find.text('Surface habitable'), findsNothing);
      expect(find.text('Assainissement'), findsNothing);
      await tester.enterText(_field('Surface utile'), '13');
      await tester.tap(find.text('Sous-sol'));
      await tester.tap(find.text('Borne de recharge'));
      for (final label in [
        'Rez-de-chaussée',
        'Étage',
        'Extérieur',
        'Porte motorisée',
        'Électricité',
        'Eau',
        'Accès sécurisé',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.pump();
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.technical, {
          PropertyColumns.usableAreaM2: 13.0,
          PropertyColumns.parkingLevel: ParkingLevel.basement,
          PropertyColumns.parkingFeatures: [ParkingFeature.chargingPoint],
          PropertyColumns.provenance: {
            PropertyColumns.usableAreaM2: 'declared',
            PropertyColumns.parkingLevel: 'declared',
            PropertyColumns.parkingFeatures: 'declared',
          },
        }),
      ).called(1);
    });

    testWidgets('an outbuilding', (tester) async {
      await pump(tester, PropertyType.outbuilding);
      expect(find.text('Le local'), findsOneWidget);
      expect(find.text('Année de construction'), findsOneWidget);
      expect(find.text('Borne de recharge'), findsNothing);
      expect(find.text('Eau'), findsOneWidget);
      await tester.enterText(_field('Année de construction'), '1880');
      await tester.pump();
    });

    testWidgets('a commercial premises', (tester) async {
      await pump(tester, PropertyType.commercial);
      expect(find.text('Chauffage'), findsWidgets);
      expect(find.text('Assainissement'), findsNothing);
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      expect(find.text('Indiquez la surface utile'), findsOneWidget);
    });

    testWidgets('a whole building', (tester) async {
      await pump(tester, PropertyType.building);
      expect(find.text('L’immeuble'), findsOneWidget);
      expect(find.text('Gros œuvre'), findsOneWidget);
      expect(find.text('Mitoyenneté'), findsNothing);
      expect(find.text('Chauffage & assainissement'), findsOneWidget);
      expect(find.text('Extérieur & équipements'), findsNothing);
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      expect(find.text('Indiquez l’année de construction'), findsOneWidget);
    });
  });
}
