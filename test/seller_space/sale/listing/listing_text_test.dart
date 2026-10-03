import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobileapp/l10n/l10n.dart';
import 'package:mobileapp/seller_space/sale/listing/listing_text.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('fr'));

  group('listingTextOf', () {
    test('a house with its facts', () {
      final text = listingTextOf(l10n, const [
        Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.house,
          livingAreaM2: 115,
          roomsCount: 5,
          bedroomsCount: 3,
          addressCity: 'Chaponost',
          constructionYear: 1998,
          outdoorEquipment: OutdoorEquipment.values,
          heatingSystems: [HeatingSystem.heatPump],
        ),
      ]);
      expect(text.title, 'Maison de 115 m² à Chaponost');
      expect(
        text.description,
        startsWith('Maison de 115 m², 5 pièces, 3 chambres à Chaponost.'),
      );
      expect(text.description, contains('Construction : 1998.'));
      expect(text.description, contains('piscine, garage'));
      expect(text.description, contains('Chauffage :'));
    });

    test('a property without facts', () {
      final text = listingTextOf(l10n, const [
        Property(id: 'p', ownerId: 'u', usableAreaM2: 12.5),
      ]);
      expect(text.title, 'Bien de 12,5 m²');
      expect(text.description, 'Bien de 12,5 m².');
      final bare = listingTextOf(l10n, const [
        Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
      ]);
      expect(bare.title, 'Terrain');
    });

    test('a lot describes each property; long texts are cut', () {
      final text = listingTextOf(l10n, [
        const Property(
          id: 'a',
          ownerId: 'u',
          propertyType: PropertyType.house,
          addressCity: 'Lyon',
        ),
        const Property(
          id: 'b',
          ownerId: 'u',
          propertyType: PropertyType.parking,
        ),
      ]);
      expect(text.title, 'Lot de 2 biens à Lyon');
      expect(text.description, contains('• Maison à Lyon.'));
      expect(text.description, contains('• Garage / parking.'));
      final noCity = listingTextOf(l10n, [
        for (var i = 0; i < 80; i++)
          Property(
            id: '$i',
            ownerId: 'u',
            propertyType: PropertyType.other,
            propertyTypeOther: 'x' * 40,
          ),
      ]);
      expect(noCity.title, 'Lot de 80 biens');
      expect(noCity.description.length, 2000);
      expect(noCity.description, endsWith('…'));
      final longTitle = listingTextOf(l10n, [
        Property(
          id: 'a',
          ownerId: 'u',
          propertyType: PropertyType.other,
          propertyTypeOther: 'y' * 150,
        ),
      ]);
      expect(longTitle.title.length, 120);
    });
  });
}
