import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/property_context/cubit/property_context_cubit.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(EditableText),
);

void main() {
  final today = DateTime(2026, 10);

  setUpAll(() {
    registerFallbackValue(SellerTunnelStep.context);
    registerFallbackValue(<String, Object?>{});
  });

  group('PropertyContextState by type', () {
    PropertyContextState state(PropertyType type) => PropertyContextState(
      today: today,
      propertyType: type,
      propertyTypeOther: ' Grange ',
      landKind: LandKind.buildable,
      parkingKind: ParkingKind.box,
      commercialUse: ' Boutique ',
      unitsCount: '6',
      purchaseYear: '2000',
      selfBuilt: true,
    );

    test('writes the precision of each type, keeping the others', () {
      expect(state(PropertyType.house).patch, {
        PropertyColumns.propertyType: PropertyType.house,
        PropertyColumns.purchaseYear: 2000,
        PropertyColumns.purchasePriceEur: null,
        PropertyColumns.selfBuilt: true,
        PropertyColumns.saleReason: null,
        PropertyColumns.previouslyEstimated: null,
      });
      expect(
        state(PropertyType.land).patch[PropertyColumns.landKind],
        LandKind.buildable,
      );
      expect(
        state(PropertyType.land).patch.containsKey(PropertyColumns.selfBuilt),
        isFalse,
      );
      expect(
        state(PropertyType.parking).patch[PropertyColumns.parkingKind],
        ParkingKind.box,
      );
      expect(
        state(PropertyType.outbuilding)
            .patch[PropertyColumns.propertyTypeOther],
        'Grange',
      );
      expect(
        state(PropertyType.commercial).patch[PropertyColumns.commercialUse],
        'Boutique',
      );
      expect(state(PropertyType.building).patch[PropertyColumns.unitsCount], 6);
      expect(
        state(PropertyType.other)
            .copyWith(propertyTypeOther: ' ')
            .patch[PropertyColumns.propertyTypeOther],
        isNull,
      );
    });

    test('checks the number of dwellings of a building', () {
      final building = state(PropertyType.building);
      expect(building.unitsCountError, isNull);
      expect(
        building.copyWith(unitsCount: '1').unitsCountError,
        PropertyContextError.unitsRange,
      );
      expect(building.copyWith(unitsCount: '1').isValid, isFalse);
      expect(
        building.copyWith(unitsCount: '501').unitsCountError,
        PropertyContextError.unitsRange,
      );
      expect(building.copyWith(unitsCount: '').unitsCountError, isNull);
      expect(
        state(PropertyType.house).copyWith(unitsCount: '1').unitsCountError,
        isNull,
      );
    });

    test('the cubit edits the precisions', () {
      final cubit = PropertyContextCubit(
        propertyRepository: MockPropertyRepository(),
        property: const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.building,
          unitsCount: 4,
          commercialUse: 'Bureau',
          landKind: LandKind.unknown,
          parkingKind: ParkingKind.garage,
        ),
        today: today,
      );
      expect(cubit.state.unitsCount, '4');
      expect(cubit.state.commercialUse, 'Bureau');
      cubit
        ..landKindToggled(LandKind.unknown)
        ..parkingKindToggled(ParkingKind.box)
        ..commercialUseChanged('Entrepôt')
        ..unitsCountChanged('12');
      expect(cubit.state.landKind, isNull);
      expect(cubit.state.parkingKind, ParkingKind.box);
      expect(cubit.state.commercialUse, 'Entrepôt');
      expect(cubit.state.unitsCount, '12');
      cubit
        ..landKindToggled(LandKind.buildable)
        ..parkingKindToggled(ParkingKind.box);
      expect(cubit.state.landKind, LandKind.buildable);
      expect(cubit.state.parkingKind, isNull);
    });
  });

  group('PropertyContextPage by type', () {
    late MockPropertyRepository repository;

    setUp(() {
      repository = MockPropertyRepository();
    });

    Future<MockSellerTunnelCubit> pump(WidgetTester tester) async {
      final view = tester.view
        ..physicalSize = const Size(390, 2400)
        ..devicePixelRatio = 1;
      addTearDown(view.reset);
      final cubit = mockSellerTunnelCubit();
      await tester.pumpTunnelPage(
        const PropertyContextPage(),
        sellerTunnelCubit: cubit,
        propertyRepository: repository,
      );
      return cubit;
    }

    testWidgets('asks the precision of each type', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Garage / parking'));
      await tester.pump();
      expect(find.text('Construit par vous$_nbsp?'), findsNothing);
      await tester.tap(find.text('Box fermé'));
      await tester.pump();

      await tester.tap(find.text('Dépendance'));
      await tester.pump();
      expect(find.text('Précisez la dépendance'), findsOneWidget);
      expect(find.text('Construit par vous$_nbsp?'), findsOneWidget);

      await tester.tap(find.text('Local commercial'));
      await tester.pump();
      await tester.enterText(_field('Usage du local'), 'Boutique');

      await tester.tap(find.text('Terrain'));
      await tester.pump();
      await tester.tap(find.text('Constructible'));
      await tester.pump();

      await tester.tap(find.text('Immeuble entier'));
      await tester.pump();
      await tester.enterText(_field('Nombre de logements'), '1');
      await tester.enterText(_field('Année d’achat'), '2001');
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      expect(find.text('Entre 2 et 500 logements'), findsOneWidget);

      await tester.enterText(_field('Nombre de logements'), '8');
      await tester.pump();
      expect(find.text('Entre 2 et 500 logements'), findsNothing);
    });

    testWidgets('saves the precision of the type', (tester) async {
      final cubit = await pump(tester);
      await tester.tap(find.text('Garage / parking'));
      await tester.pump();
      await tester.tap(find.text('Place extérieure'));
      await tester.enterText(_field('Année d’achat'), '2001');
      await tester.tap(find.text('Continuer'));
      await tester.pump();
      expect(
        savedStepPatch(cubit, SellerTunnelStep.context),
        containsPair(PropertyColumns.parkingKind, ParkingKind.outdoorSpace),
      );
    });

    testWidgets('lists every kind of land and parking', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Terrain'));
      await tester.pump();
      for (final label in [
        'Constructible',
        'Non constructible',
        'Je ne sais pas',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Garage / parking'));
      await tester.pump();
      for (final label in [
        'Box fermé',
        'Garage',
        'Place couverte',
        'Place extérieure',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}
