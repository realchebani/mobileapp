import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/widgets/room_sheet.dart';
import 'package:mobileapp/ui/ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:property_repository/property_repository.dart';

import '../../../helpers/helpers.dart';

const _nbsp = ' ';

const _living = Room(
  id: 'r1',
  propertyId: 'property-id',
  name: 'Séjour',
  level: RoomLevel.groundFloor,
  areaM2: 38.5,
  floorCovering: 'parquet_chene',
  isMain: true,
);

const _bedroom = Room(
  id: 'r2',
  propertyId: 'property-id',
  name: 'Chambre 1',
  level: RoomLevel.firstFloor,
  areaM2: 12.4,
  sortOrder: 1,
  floorCovering: 'moquette',
  isMain: true,
);

const _wc = Room(
  id: 'r3',
  propertyId: 'property-id',
  name: 'WC',
  level: RoomLevel.firstFloor,
  areaM2: 1.6,
  sortOrder: 2,
);

const _garage = Room(
  id: 'r4',
  propertyId: 'property-id',
  name: 'Garage',
  level: RoomLevel.groundFloor,
  areaM2: 18,
  sortOrder: 3,
  isAnnex: true,
);

const _property = Property(
  id: 'property-id',
  ownerId: 'user-id',
  provenance: {'construction_year': 'document'},
);

SellerTunnelState _state({
  List<Room> rooms = const [_living, _bedroom, _wc],
  SellerTunnelSaveStatus saveStatus = SellerTunnelSaveStatus.idle,
}) => SellerTunnelState(
  status: SellerTunnelStatus.success,
  saveStatus: saveStatus,
  property: _property,
  rooms: rooms,
);

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(RealestyTextField, label),
  matching: find.byType(TextField),
);

void main() {
  late MockPropertyRepository repository;

  setUpAll(() => registerFallbackValue(_living));

  setUp(() {
    repository = MockPropertyRepository();
    when(() => repository.saveRoom(any())).thenAnswer(
      (invocation) async => invocation.positionalArguments.single as Room,
    );
    when(() => repository.deleteRoom(any())).thenAnswer((_) async {});
  });

  Future<MockSellerTunnelCubit> pump(
    WidgetTester tester, {
    SellerTunnelState? state,
    double height = 1400,
    MockGoRouter? goRouter,
  }) async {
    tester.view
      ..physicalSize = Size(390, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = mockSellerTunnelCubit(state ?? _state());
    when(() => cubit.updateChildren(rooms: any(named: 'rooms')))
        .thenReturn(null);
    await tester.pumpTunnelPage(
      const SurfacesPage(),
      sellerTunnelCubit: cubit,
      propertyRepository: repository,
      goRouter: goRouter,
    );
    return cubit;
  }

  group(SurfacesPage, () {
    testWidgets('shows the rooms by level and the living area', (tester) async {
      await pump(tester);

      expect(find.text('Étape 5 · Pièces'), findsOneWidget);
      expect(
        find.text(
          'Et voilà$_nbsp! Nous obtenons 52,5${_nbsp}m² habitables '
          'répartis sur 2 pièces principales. Tout vous semble '
          'correct$_nbsp?',
        ),
        findsOneWidget,
      );
      expect(find.text('3 pièces saisies'), findsOneWidget);
      expect(find.text('REZ-DE-CHAUSSÉE'), findsOneWidget);
      expect(find.text('ÉTAGE'), findsOneWidget);
      expect(find.text('38,5'), findsOneWidget);
      expect(find.text('Parquet chêne'), findsOneWidget);
      expect(find.text('Moquette'), findsOneWidget);
      expect(find.text('Surface habitable'), findsOneWidget);
      expect(find.textContaining('Annexes'), findsNothing);
      expect(find.text('Annexe'), findsNothing);
      expect(find.text('52,5${_nbsp}m²'), findsOneWidget);
      expect(find.bySemanticsLabel('Modifier Séjour'), findsOneWidget);
      expect(find.text('Tout est correct, continuer'), findsOneWidget);
    });

    testWidgets('counts the annexes apart from the living area', (
      tester,
    ) async {
      final cubit = await pump(
        tester,
        state: _state(rooms: const [_living, _bedroom, _wc, _garage]),
      );

      expect(
        find.textContaining('Nous obtenons 52,5${_nbsp}m² habitables'),
        findsOneWidget,
      );
      expect(find.text('Annexe'), findsOneWidget);
      expect(find.text('Surface habitable'), findsOneWidget);
      expect(find.text('52,5${_nbsp}m²'), findsOneWidget);
      expect(find.text('Annexes$_nbsp: 18,0${_nbsp}m²'), findsOneWidget);

      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pumpAndSettle();
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.surfaces, {
          PropertyColumns.livingAreaM2: 52.5,
          PropertyColumns.annexAreaM2: 18.0,
          PropertyColumns.provenance: {
            'construction_year': 'document',
            'living_area_m2': 'declared',
            'annex_area_m2': 'declared',
          },
        }),
      ).called(1);
    });

    testWidgets('annexes alone cannot continue', (tester) async {
      final cubit = await pump(tester, state: _state(rooms: const [_garage]));
      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ajoutez au moins une pièce habitable pour continuer.'),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));
    });

    testWidgets('templates the agent message by count', (tester) async {
      await pump(tester, state: _state(rooms: const [_wc]));
      expect(
        find.text(
          'Et voilà$_nbsp! Nous obtenons 1,6${_nbsp}m² habitables. Tout '
          'vous semble correct$_nbsp?',
        ),
        findsOneWidget,
      );
      expect(find.text('1 pièce saisie'), findsOneWidget);
    });

    testWidgets('one main room', (tester) async {
      await pump(tester, state: _state(rooms: const [_living]));
      expect(
        find.textContaining('répartis sur 1 pièce principale.'),
        findsOneWidget,
      );
    });

    testWidgets('without rooms, explains and requires one', (tester) async {
      final cubit = await pump(tester, state: _state(rooms: const []));

      expect(
        find.text(
          'Ajoutons vos pièces une à une$_nbsp: pour chacune, son niveau et '
          'sa surface. Je calcule la surface habitable au fur et à mesure.',
        ),
        findsOneWidget,
      );
      expect(find.text('Aucune pièce pour l’instant.'), findsOneWidget);
      expect(find.text('0,0${_nbsp}m²'), findsOneWidget);
      expect(find.byType(RealestyBadge), findsNothing);

      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Ajoutez au moins une pièce habitable pour continuer.'),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));
    });

    testWidgets('adds a room on the level of the last one', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Ajouter une pièce'));
      await tester.pumpAndSettle();
      expect(find.byType(RoomSheet), findsOneWidget);
      expect(find.text('Étage').last, findsOneWidget);

      await tester.tap(find.text('Chambre'));
      await tester.enterText(_field('Surface'), '10,2');
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();

      expect(find.text('Chambre 2'), findsOneWidget);
      expect(find.text('62,7${_nbsp}m²'), findsOneWidget);
      expect(find.text('4 pièces saisies'), findsOneWidget);
    });

    testWidgets('a dismissed sheet changes nothing', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Ajouter une pièce'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Modifier WC'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(RoomSheet), findsNothing);
      expect(find.text('52,5${_nbsp}m²'), findsOneWidget);
    });

    testWidgets('edits and deletes rooms', (tester) async {
      await pump(tester);

      await tester.tap(find.bySemanticsLabel('Modifier Séjour'));
      await tester.pumpAndSettle();
      expect(find.text('Modifier la pièce'), findsOneWidget);
      await tester.enterText(_field('Surface'), '40');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('40,0'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Modifier WC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette pièce'));
      await tester.pumpAndSettle();
      expect(find.text('WC'), findsNothing);
      expect(find.text('52,4${_nbsp}m²'), findsOneWidget);
    });

    testWidgets('continue saves the rooms, then the living area', (
      tester,
    ) async {
      final cubit = await pump(tester);

      await tester.tap(find.bySemanticsLabel('Modifier WC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette pièce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pumpAndSettle();

      verify(() => repository.deleteRoom('r3')).called(1);
      verifyNever(() => repository.saveRoom(any()));
      verify(() => cubit.updateChildren(rooms: const [_living, _bedroom]))
          .called(1);
      verify(
        () => cubit.saveAndContinue(SellerTunnelStep.surfaces, {
          PropertyColumns.livingAreaM2: 50.9,
          PropertyColumns.annexAreaM2: 0.0,
          PropertyColumns.provenance: {
            'construction_year': 'document',
            'living_area_m2': 'declared',
            'annex_area_m2': 'declared',
          },
        }),
      ).called(1);
    });

    testWidgets('a failed save shows an error', (tester) async {
      when(() => repository.deleteRoom(any())).thenThrow(Exception());
      final cubit = await pump(tester);

      await tester.tap(find.bySemanticsLabel('Modifier WC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette pièce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'L’enregistrement a échoué. Vérifiez votre connexion et réessayez.',
        ),
        findsOneWidget,
      );
      verifyNever(() => cubit.saveAndContinue(any(), any()));
      // The tunnel keeps the rows still stored.
      verify(() => cubit.updateChildren(rooms: const [_living, _bedroom, _wc]))
          .called(1);
    });

    testWidgets('is disabled while saving', (tester) async {
      final completer = Completer<void>();
      when(() => repository.deleteRoom(any()))
          .thenAnswer((_) => completer.future);
      await pump(tester);
      await tester.tap(find.bySemanticsLabel('Modifier WC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer cette pièce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pump();

      expect(
        tester
            .widget<RealestyButton>(
              find.widgetWithText(RealestyButton, 'Ajouter une pièce'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.bySemanticsLabel('Modifier Séjour'));
      await tester.pump();
      expect(find.byType(RoomSheet), findsNothing);
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
      expect(find.bySemanticsLabel('Retour'), findsNothing);
      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('is disabled while the tunnel saves', (tester) async {
      await pump(
        tester,
        state: _state(saveStatus: SellerTunnelSaveStatus.inProgress),
      );
      expect(
        tester.widget<AgentActionBar>(find.byType(AgentActionBar)).isLoading,
        isTrue,
      );
      await tester.tap(find.text('Ajouter une pièce'));
      await tester.pump();
      expect(find.byType(RoomSheet), findsNothing);
    });

    testWidgets('goes back to the method', (tester) async {
      final goRouter = MockGoRouter();
      when(() => goRouter.go(any())).thenReturn(null);
      await pump(tester, goRouter: goRouter);

      await tester.tap(find.bySemanticsLabel('Retour'));

      verify(() => goRouter.go(auditRoute(SellerTunnelStep.method))).called(1);
    });

    testWidgets('reveals the error on a small screen', (tester) async {
      await pump(tester, state: _state(rooms: const []), height: 500);
      await tester.tap(find.text('Tout est correct, continuer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ajoutez au moins une pièce habitable pour continuer.'),
        findsOneWidget,
      );
    });
  });
}
