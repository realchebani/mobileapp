import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/seller_space.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../helpers/helpers.dart';
import '../pump_seller_space.dart';

void main() {
  const ownerId = 'user-id';
  const house = Property(
    id: 'house',
    ownerId: ownerId,
    propertyType: PropertyType.house,
    addressCity: 'Chaponost',
  );
  const land = Property(
    id: 'land',
    ownerId: ownerId,
    propertyType: PropertyType.land,
  );
  const created = Property(
    id: 'new',
    ownerId: ownerId,
    propertyType: PropertyType.parking,
  );

  late MockGoRouter goRouter;
  late MockPropertyRepository repository;
  late MockSellerPropertiesCubit properties;

  setUp(() {
    goRouter = MockGoRouter();
    when(() => goRouter.go(any())).thenReturn(null);
    when(() => goRouter.canPop()).thenReturn(true);
    when(() => goRouter.pop<Object?>()).thenReturn(null);
    repository = MockPropertyRepository();
    when(
      () => repository.createProperty(
        id: any(named: 'id'),
        ownerId: any(named: 'ownerId'),
        type: any(named: 'type'),
        lotId: any(named: 'lotId'),
      ),
    ).thenAnswer((_) async => created);
    when(
      () => repository.copyOwners(
        fromPropertyId: any(named: 'fromPropertyId'),
        toPropertyId: any(named: 'toPropertyId'),
      ),
    ).thenAnswer((_) async => []);
    when(() => repository.getDocuments(any())).thenAnswer((_) async => []);
  });

  Future<void> pump(
    WidgetTester tester, {
    List<Property> existing = const [house, land],
  }) async {
    properties = mockSellerPropertiesCubit(properties: existing);
    await tester.pumpSellerSpacePage(
      const NewPropertyPage(),
      sellerPropertiesCubit: properties,
      propertyRepository: repository,
      goRouter: goRouter,
    );
  }

  group(NewPropertyPage, () {
    testWidgets('creates the property, then opens V1', (tester) async {
      usePhoneSurface();
      await pump(tester);
      expect(find.text('Ajouter un bien'), findsOneWidget);
      expect(find.text('Garage / parking'), findsOneWidget);

      await tester.tap(find.text('Commencer l’audit'));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez le type de bien'), findsOneWidget);

      await tester.tap(find.text('Garage / parking'));
      await tester.scrollUntilVisible(find.text('Depuis Terrain'), 100);
      await tester.ensureVisible(find.text('Depuis Terrain'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Depuis Terrain'));
      await tester.tap(find.text('La pièce d’identité'));
      await tester.tap(find.text('Les propriétaires'));
      await tester.pump();
      await tester.tap(find.text('Commencer l’audit'));
      await tester.pumpAndSettle();

      verify(
        () => repository.createProperty(
          id: any(named: 'id'),
          ownerId: any(named: 'ownerId'),
          type: PropertyType.parking,
        ),
      ).called(1);
      verify(() => properties.propertyChanged(created)).called(1);
      verify(() => goRouter.go('/vendeur/biens/new/audit/proprietaires'))
          .called(1);
    });

    testWidgets('offers a lot with an existing property', (tester) async {
      usePhoneSurface();
      await pump(tester, existing: const [house]);
      expect(find.text('Depuis Maison · Chaponost'), findsOneWidget);
      await tester.ensureVisible(find.text('Avec Maison · Chaponost'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avec Maison · Chaponost'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.widgetWithText(RealestyListItem, 'Avec Maison · Chaponost'),
          matching: find.byType(RealestyIcon),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Non, vendu seul'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.pop<Object?>()).called(1);
      when(() => goRouter.canPop()).thenReturn(false);
      await tester.tap(find.bySemanticsLabel('Retour'));
      verify(() => goRouter.go('/vendeur')).called(1);
    });

    testWidgets('tells the errors', (tester) async {
      usePhoneSurface();
      var calls = 0;
      when(
        () => repository.createProperty(
          id: any(named: 'id'),
          ownerId: any(named: 'ownerId'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async {
        if (calls++ == 0) throw const PropertySaveFailure();
        throw const PropertyLimitFailure();
      });
      await pump(tester, existing: const []);
      await tester.tap(find.text('Maison'));
      await tester.tap(find.text('Commencer l’audit'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le bien n’a pas pu être créé. Réessayez.'),
        findsOneWidget,
      );
      // Past the first snackbar.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Commencer l’audit'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Vous avez atteint la limite de 5 biens pendant la phase de test.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tells when the information could not be copied', (
      tester,
    ) async {
      usePhoneSurface();
      when(
        () => repository.copyOwners(
          fromPropertyId: any(named: 'fromPropertyId'),
          toPropertyId: any(named: 'toPropertyId'),
        ),
      ).thenAnswer((_) async => throw const PropertySaveFailure());
      await pump(tester, existing: const [house]);
      await tester.tap(find.text('Maison'));
      await tester.tap(find.text('Commencer l’audit'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Le bien est créé, mais certaines informations n’ont pas pu être '
          'reprises. Réessayez.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('tells when the property could not join the lot', (
      tester,
    ) async {
      usePhoneSurface();
      when(
        () => repository.createLotWith(
          id: any(named: 'id'),
          propertyIds: any(named: 'propertyIds'),
        ),
      ).thenAnswer((_) async => throw const PropertySaveFailure());
      await pump(tester, existing: const [house]);
      await tester.tap(find.text('Garage / parking'));
      await tester.ensureVisible(find.text('Avec Maison · Chaponost'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avec Maison · Chaponost'));
      await tester.tap(find.text('Commencer l’audit'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Le bien est créé, mais il n’a pas pu rejoindre le lot. Réessayez.',
        ),
        findsOneWidget,
      );
      verify(() => properties.propertyChanged(created)).called(1);
    });
  });
}
