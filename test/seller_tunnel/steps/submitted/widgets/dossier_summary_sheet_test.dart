import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:mobileapp/seller_tunnel/steps/submitted/widgets/dossier_summary_sheet.dart';
import 'package:property_repository/property_repository.dart';

import '../../../../helpers/helpers.dart';

const nb = '\u00a0';
const _id = 'property-id';

Room _room(double area, {bool isAnnex = false}) =>
    Room(propertyId: _id, name: 'Pièce', areaM2: area, isAnnex: isAnnex);

LifestyleItem _item(LifestyleItemKind kind) =>
    LifestyleItem(propertyId: _id, kind: kind, label: 'x');

void main() {
  Future<void> pump(WidgetTester tester, SellerTunnelState state) async {
    usePhoneSurface();
    tester.view.physicalSize = const Size(390, 2400);
    await tester.pumpTunnelPage(DossierSummarySheet(state: state));
  }

  SellerTunnelState full(Property property) => SellerTunnelState(
    status: SellerTunnelStatus.success,
    property: property,
    owners: const [
      PropertyOwner(
        propertyId: _id,
        position: 1,
        firstName: 'Sophie',
        lastName: 'Durand',
      ),
      PropertyOwner(
        propertyId: _id,
        position: 2,
        firstName: 'Marc',
        lastName: 'Durand',
      ),
    ],
    parcels: const [
      PropertyParcel(
        propertyId: _id,
        idu: '69043000AB0123',
        section: 'AB',
        numero: '0123',
        areaM2: 540,
      ),
      PropertyParcel(propertyId: _id, idu: '69043000AB0124'),
    ],
    rooms: [
      _room(38.5),
      _room(12),
      _room(18, isAnnex: true),
      // EPIC-14: a room description.
      const Room(
        propertyId: _id,
        name: 'Séjour',
        areaM2: 0.5,
        description: 'Ouvert sur la cuisine',
      ),
    ],
    lifestyleItems: [
      _item(LifestyleItemKind.asset),
      _item(LifestyleItemKind.asset),
      _item(LifestyleItemKind.watchPoint),
    ],
    documents: const [
      PropertyDocument(
        id: 'd1',
        propertyId: _id,
        kind: DocumentKind.titleDeed,
        storagePath: 'a/b',
      ),
    ],
  );

  testWidgets('lists the main answers of each step', (tester) async {
    await pump(
      tester,
      full(
        const Property(
          id: _id,
          ownerId: 'user-id',
          addressLabel: '12 rue des Lilas 69630 Chaponost',
          propertyType: PropertyType.house,
          purchaseYear: 2009,
          constructionYear: 1998,
          livingAreaM2: 115.5,
          roomsCount: 5,
          bedroomsCount: 3,
          levels: PropertyLevels.oneUpperFloor,
          heatingSystems: [HeatingSystem.heatPump, HeatingSystem.wood],
          sanitation: Sanitation.mainsSewer,
        ),
      ),
    );
    for (final text in [
      'Aperçu de mes données',
      'Propriétaire 1',
      'Sophie Durand',
      'Marc Durand',
      '12 rue des Lilas 69630 Chaponost',
      'Section AB n°${nb}0123, 69043000AB0124',
      '540${nb}m²',
      'Maison',
      '2009',
      '1998',
      '115,5${nb}m²',
      '5',
      '3',
      'R+1',
      'Pompe à chaleur, Poêle à bois',
      'Tout-à-l’égout',
      '3 pièces · 51${nb}m² habitables',
      'Ouvert sur la cuisine',
      'Annexes',
      '1 annexe · 18${nb}m²',
      '2 éléments',
      '1 élément',
      '1 document',
    ]) {
      expect(find.text(text), findsOne, reason: text);
    }
  });

  testWidgets('shows "Non renseigné" for missing answers', (tester) async {
    await pump(
      tester,
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(id: _id, ownerId: 'user-id'),
      ),
    );
    expect(find.text('Non renseigné'), findsNWidgets(13));
    expect(
      find.text('Aperçu en lecture seule de vos réponses enregistrées.'),
      findsOne,
    );
    expect(find.text('Aucun'), findsNWidgets(2));
    expect(find.text('Aucun document'), findsOne);
  });

  for (final (type, other, label) in [
    (PropertyType.apartment, null, 'Appartement'),
    (PropertyType.land, null, 'Terrain'),
    (PropertyType.other, ' ', 'Non renseigné'),
    (PropertyType.other, 'Local commercial', 'Local commercial'),
  ]) {
    testWidgets('property type $label', (tester) async {
      await pump(
        tester,
        SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: _id,
            ownerId: 'user-id',
            propertyType: type,
            propertyTypeOther: other,
          ),
        ),
      );
      expect(find.text(label), findsWidgets);
    });
  }

  testWidgets('other technical values', (tester) async {
    for (final (levels, systems, sanitation, texts) in [
      (
        PropertyLevels.singleStorey,
        [HeatingSystem.electricity],
        Sanitation.septicTank,
        ['Plain-pied', 'Électrique', 'Fosse septique'],
      ),
      (
        PropertyLevels.twoOrMoreUpperFloors,
        [HeatingSystem.gas, HeatingSystem.pellets, HeatingSystem.fireplace],
        Sanitation.soakaway,
        [
          'R+2 et plus',
          'Gaz, Poêle à granulés, Cheminée / insert',
          'Puits perdu',
        ],
      ),
      (
        null,
        [HeatingSystem.fuelOil, HeatingSystem.districtHeating],
        null,
        ['Fioul, Réseau de chaleur'],
      ),
      (
        null,
        [HeatingSystem.solar, HeatingSystem.other],
        null,
        ['Solaire, Autre'],
      ),
    ]) {
      await pump(
        tester,
        SellerTunnelState(
          status: SellerTunnelStatus.success,
          property: Property(
            id: _id,
            ownerId: 'user-id',
            levels: levels,
            heatingSystems: systems,
            sanitation: sanitation,
            roomsCount: 1,
          ),
        ),
      );
      for (final text in texts) {
        expect(find.text(text), findsOne, reason: text);
      }
      expect(find.text('1'), findsOne);
    }
  });

  testWidgets('counts the photos, in total and by room (EPIC-15)', (
    tester,
  ) async {
    await pump(
      tester,
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(id: _id, ownerId: 'user-id'),
        rooms: [
          Room(propertyId: _id, name: 'Séjour', areaM2: 30, photosCount: 3),
          Room(propertyId: _id, name: 'WC', areaM2: 2),
        ],
      ),
    );
    await tester.scrollUntilVisible(find.text('Photos · Séjour'), 200);
    expect(find.text('3 photos'), findsNWidgets(2));
    expect(find.text('Photos · WC'), findsNothing);
  });

  testWidgets('blank owner names are not given', (tester) async {
    await pump(
      tester,
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: _id,
          ownerId: 'user-id',
          status: PropertyStatus.submitted,
        ),
        owners: [
          PropertyOwner(
            propertyId: _id,
            position: 1,
            firstName: ' ',
            lastName: '',
          ),
        ],
      ),
    );
    expect(find.text('Non renseigné'), findsNWidgets(13));
    expect(
      find.text('Aperçu en lecture seule des réponses transmises à l’expert.'),
      findsOne,
    );
  });

  testWidgets('EPIC-16: the notes of each step', (tester) async {
    await pump(
      tester,
      const SellerTunnelState(
        status: SellerTunnelStatus.success,
        property: Property(
          id: _id,
          ownerId: 'u',
          propertyType: PropertyType.house,
          stepNotes: {
            'location': 'Terrain en pente',
            'context': 'Vendu meublé',
            'technical': 'Grenier aménageable',
            'rooms': 'Combles isolés',
            'lifestyle': 'Marché le samedi',
          },
        ),
      ),
    );
    expect(find.text('Notes complémentaires'), findsNWidgets(5));
    for (final note in [
      'Terrain en pente',
      'Vendu meublé',
      'Grenier aménageable',
      'Combles isolés',
      'Marché le samedi',
    ]) {
      expect(find.text(note), findsOneWidget);
    }
  });
}
