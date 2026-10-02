import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';
import 'package:property_repository/property_repository.dart';

void main() {
  group(PropertyTypeProfile, () {
    PropertyTypeProfile of(PropertyType? type) => PropertyTypeProfile.of(type);

    test('matches the parity fixture of the Edge Functions', () {
      final fixture = jsonDecode(
        File(
          'supabase/functions/tests/fixtures/'
          'property_type_profiles.json',
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final type in PropertyType.values) {
        final row = fixture[type.value] as Map<String, dynamic>;
        expect(of(type).voice, row['voice'], reason: type.value);
        expect(of(type).estimate, row['estimate'], reason: type.value);
      }
      expect(of(null), of(null));
      expect(of(PropertyType.house).props, [PropertyType.house]);
    });

    test('a house goes through every screen', () {
      final house = of(PropertyType.house);
      expect(house.steps, hasLength(8));
      expect(house.stepCount, 7);
      expect(
        house.nextAfter(SellerTunnelStep.technical),
        SellerTunnelStep.method,
      );
      expect(
        house.nextAfter(SellerTunnelStep.documents),
        SellerTunnelStep.submitted,
      );
      expect(
        house.nextAfter(SellerTunnelStep.submitted),
        SellerTunnelStep.submitted,
      );
      expect(house.previousBefore(SellerTunnelStep.owners), isNull);
      expect(house.previousBefore(SellerTunnelStep.submitted), isNull);
      expect(
        house.previousBefore(SellerTunnelStep.surfaces),
        SellerTunnelStep.method,
      );
      expect(house.positionOf(SellerTunnelStep.surfaces), 5);
      expect(house.positionOf(SellerTunnelStep.submitted), 7);
      expect(house.resumeAt(5), SellerTunnelStep.method);
      expect(house.resumeAt(8), SellerTunnelStep.submitted);
      expect(house.completedAt(5), 4);
    });

    test('a garage skips the rooms and the neighbourhood', () {
      final garage = of(PropertyType.parking);
      expect(garage.steps, [
        SellerTunnelStep.owners,
        SellerTunnelStep.location,
        SellerTunnelStep.context,
        SellerTunnelStep.technical,
        SellerTunnelStep.documents,
      ]);
      expect(garage.stepCount, 5);
      expect(
        garage.nextAfter(SellerTunnelStep.technical),
        SellerTunnelStep.documents,
      );
      expect(
        garage.previousBefore(SellerTunnelStep.documents),
        SellerTunnelStep.technical,
      );
      expect(garage.positionOf(SellerTunnelStep.documents), 5);
      expect(garage.positionOf(SellerTunnelStep.lifestyle), 5);
      expect(garage.resumeAt(5), SellerTunnelStep.documents);
      expect(garage.includes(SellerTunnelStep.method), isFalse);
      expect(garage.includes(SellerTunnelStep.submitted), isTrue);
      expect(garage.voice, isFalse);
      expect(garage.estimate, isTrue);
      expect(garage.detail, PropertyTypeDetail.parkingKind);
      expect(garage.parkingFeatureChoices, ParkingFeature.values);
    });

    test('each type has its own questions and documents', () {
      expect(of(PropertyType.land).detail, PropertyTypeDetail.landKind);
      expect(of(PropertyType.land).asksSelfBuilt, isFalse);
      expect(of(PropertyType.outbuilding).detail, PropertyTypeDetail.otherText);
      expect(
        of(PropertyType.commercial).detail,
        PropertyTypeDetail.commercialUse,
      );
      expect(of(PropertyType.commercial).asksNeighbourhood, isFalse);
      expect(of(PropertyType.commercial).requiredTechnicalFields, {
        TechnicalField.usableArea,
      });
      expect(of(PropertyType.building).detail, PropertyTypeDetail.unitsCount);
      expect(of(PropertyType.other).detail, PropertyTypeDetail.otherText);
      expect(
        of(PropertyType.apartment).technicalFields,
        isNot(contains(TechnicalField.levels)),
      );
      expect(
        of(PropertyType.house).documentKinds,
        contains(DocumentKind.energyBills),
      );
      expect(of(PropertyType.parking).documentKinds, [
        DocumentKind.titleDeed,
        DocumentKind.propertyTax,
        DocumentKind.identityDocument,
        DocumentKind.other,
      ]);
      expect(of(null).steps, of(PropertyType.house).steps);
    });

    test('clears what a type does not ask when the dossier is sent', () {
      final cleared = of(PropertyType.parking).clearedOnSubmit;
      expect(cleared[PropertyColumns.livingAreaM2], isNull);
      expect(cleared.containsKey(PropertyColumns.livingAreaM2), isTrue);
      expect(cleared[PropertyColumns.heatingSystems], isEmpty);
      expect(cleared[PropertyColumns.outdoorEquipment], isEmpty);
      expect(cleared.containsKey(PropertyColumns.parkingKind), isFalse);
      expect(cleared.containsKey(PropertyColumns.usableAreaM2), isFalse);
      expect(cleared.containsKey(PropertyColumns.measurementMethod), isTrue);
      expect(cleared.containsKey(PropertyColumns.noiseLevel), isTrue);
      expect(cleared.containsKey(PropertyColumns.secretNote), isTrue);
      expect(cleared.containsKey(PropertyColumns.selfBuilt), isTrue);

      final commercial = of(PropertyType.commercial).clearedOnSubmit;
      expect(commercial.containsKey(PropertyColumns.noiseLevel), isTrue);
      expect(commercial.containsKey(PropertyColumns.secretNote), isFalse);
      expect(
        of(PropertyType.house).clearedOnSubmit
            .containsKey(PropertyColumns.parkingFeatures),
        isTrue,
      );
      expect(
        of(PropertyType.house).clearedOnSubmit[PropertyColumns.parkingFeatures],
        isEmpty,
      );
    });

    test('clearedFrom keeps only the answers that have a value', () {
      const garage = Property(
        id: 'p',
        ownerId: 'u',
        propertyType: PropertyType.parking,
        livingAreaM2: 90,
        heatingSystems: [HeatingSystem.gas],
        selfBuilt: false,
        parkingKind: ParkingKind.box,
      );
      expect(of(PropertyType.parking).clearedFrom(garage), {
        PropertyColumns.livingAreaM2: null,
        PropertyColumns.heatingSystems: isEmpty,
        PropertyColumns.selfBuilt: null,
      });
    });

    test('scores the answers asked for each type', () {
      const full = Property(
        id: 'p',
        ownerId: 'u',
        addressLabel: 'x',
        parcelConfirmed: true,
        propertyType: PropertyType.house,
        purchaseYear: 2000,
        constructionYear: 1990,
        livingAreaM2: 100,
        roomsCount: 4,
        heatingSystems: [HeatingSystem.gas],
        sanitation: Sanitation.mainsSewer,
        measurementMethod: MeasurementMethod.manual,
        noiseLevel: 3,
        parkingKind: ParkingKind.box,
        usableAreaM2: 12,
      );
      for (final type in PropertyType.values) {
        expect(
          of(type).scoredAnswers(full),
          everyElement(isTrue),
          reason: type.value,
        );
      }
      expect(of(PropertyType.parking).scoredAnswers(full), hasLength(5));
      expect(of(PropertyType.commercial).scoredAnswers(full), hasLength(6));
      expect(of(null).scoredAnswers(full), hasLength(11));
    });
  });
}
