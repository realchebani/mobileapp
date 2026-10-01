import 'package:property_repository/property_repository.dart';
import 'package:test/test.dart';

void main() {
  final fullRow = <String, dynamic>{
    'id': 'p1',
    'owner_id': 'u1',
    'status': 'submitted',
    'current_step': 3,
    'ownership_type': 'multiple',
    'address_label': '12 rue de la Colombe 69630 Chaponost',
    'address_housenumber': '12',
    'address_street': 'rue de la Colombe',
    'address_postcode': '69630',
    'address_city': 'Chaponost',
    'address_citycode': '69043',
    'address_ban_id': '69043_0120_00012',
    'lat': 45.7,
    'lng': 4.74,
    'parcel_confirmed': true,
    'special_situations': ['servitude_passage', 'unknown', 'autre'],
    'special_situation_other': 'Puits commun',
    'property_type': 'maison',
    'property_type_other': null,
    'purchase_year': 2012,
    'purchase_price_eur': 320000,
    'self_built': false,
    'sale_reason': 'agrandissement',
    'previously_estimated': true,
    'construction_year': 1998,
    'orientation': 'Sud',
    'living_area_m2': 115,
    'living_room_area_m2': 38.5,
    'annex_area_m2': 24.5,
    'rooms_count': 5,
    'bedrooms_count': 3,
    'levels': 'r1',
    'wall_material': 'parpaing',
    'adjacency': 'independant',
    'roof_type': 'Tuiles',
    'roof_year': 2016,
    'heating_energy': 'pac',
    'heating_systems': ['pac', 'granules'],
    'heat_pump_type': 'Air / eau',
    'heat_pump_year': 2021,
    'sanitation': 'tout_a_l_egout',
    'outdoor_equipment': ['piscine', 'garage'],
    'pool_type': 'Enterrée · liner',
    'pool_length_m': 8,
    'pool_width_m': 4,
    'measurement_method': 'manual',
    'noise_level': 3,
    'overlooking': 'leger',
    'secret_note': 'Boulangerie',
    'provenance': {
      'roof_year': 'declared',
      'heat_pump_year': {'source': 'document', 'document_id': 'd1'},
    },
    'transparency_score': 72,
    'submitted_at': '2026-09-24T16:42:00.000Z',
    'notify_push': false,
    'ai_estimate_low_eur': 495000,
    'ai_estimate_median_eur': 518000,
    'ai_estimate_high_eur': 540000,
    'ai_estimate_computed_at': '2026-09-24T17:00:00.000Z',
    'created_at': '2026-09-20T10:00:00.000Z',
    'updated_at': '2026-09-24T16:42:00.000Z',
  };

  group(Property, () {
    test('parses a full row', () {
      final property = Property.fromJson(fullRow);
      expect(property.id, 'p1');
      expect(property.ownerId, 'u1');
      expect(property.status, PropertyStatus.submitted);
      expect(property.currentStep, 3);
      expect(property.ownershipType, OwnershipType.multiple);
      expect(property.lat, 45.7);
      expect(property.specialSituations, [
        SpecialSituation.rightOfWay,
        SpecialSituation.other,
      ]);
      expect(property.propertyType, PropertyType.house);
      expect(property.saleReason, SaleReason.moreSpace);
      expect(property.livingAreaM2, 115.0);
      expect(property.annexAreaM2, 24.5);
      expect(property.levels, PropertyLevels.oneUpperFloor);
      expect(property.wallMaterial, WallMaterial.concreteBlock);
      expect(property.adjacency, Adjacency.detached);
      expect(property.heatingEnergy, HeatingEnergy.heatPump);
      expect(property.heatingSystems, [
        HeatingSystem.heatPump,
        HeatingSystem.pellets,
      ]);
      expect(property.sanitation, Sanitation.mainsSewer);
      expect(property.outdoorEquipment, [
        OutdoorEquipment.pool,
        OutdoorEquipment.garage,
      ]);
      expect(property.poolLengthM, 8.0);
      expect(property.measurementMethod, MeasurementMethod.manual);
      expect(property.overlooking, Overlooking.slight);
      expect(property.notifyPush, isFalse);
      expect(property.submittedAt, DateTime.utc(2026, 9, 24, 16, 42));
      expect(property.aiEstimateMedianEur, 518000);
    });

    test('round-trips through toJson', () {
      final property = Property.fromJson(fullRow);
      expect(Property.fromJson(property.toJson()), property);
      expect(property.toJson()['special_situations'], [
        'servitude_passage',
        'autre',
      ]);
      expect(property.toJson()['heating_systems'], ['pac', 'granules']);
    });

    test('defaults a minimal row', () {
      final property = Property.fromJson(const {'id': 'p', 'owner_id': 'u'});
      expect(property, const Property(id: 'p', ownerId: 'u'));
      expect(property.status, PropertyStatus.draft);
      expect(property.currentStep, 1);
      expect(property.parcelConfirmed, isFalse);
      expect(property.specialSituations, isEmpty);
      expect(property.heatingSystems, isEmpty);
      expect(property.provenance, isEmpty);
      expect(property.notifyPush, isTrue);
      expect(Property.fromJson(property.toJson()), property);
    });

    test('provenanceOf reads values and objects, defaulting to declared', () {
      final property = Property.fromJson(fullRow);
      expect(
        property.provenanceOf(PropertyColumns.heatPumpYear),
        Provenance.document,
      );
      expect(
        property.provenanceOf(PropertyColumns.roofYear),
        Provenance.declared,
      );
      expect(
        property.provenanceOf(PropertyColumns.constructionYear),
        Provenance.declared,
      );
    });

    test('mergeProvenance keeps the other entries', () {
      final property = Property.fromJson(fullRow);
      expect(
        property.mergeProvenance({
          PropertyColumns.roofYear: Provenance.document,
          PropertyColumns.poolType: Provenance.expert,
        }),
        {
          'roof_year': 'document',
          'heat_pump_year': {'source': 'document', 'document_id': 'd1'},
          'pool_type': 'expert',
        },
      );
    });

    test('has 7 steps', () {
      expect(Property.stepCount, 7);
    });
  });

  group('enums', () {
    test('parse their stored values', () {
      expect(
        parseDbEnum(PropertyStatus.values, 'in_review'),
        PropertyStatus.inReview,
      );
      expect(parseDbEnum(PropertyStatus.values, 'nope'), isNull);
      expect(parseDbEnum(PropertyStatus.values, null), isNull);
      expect(parseDbEnumList(Glazing.values, null), isEmpty);
    });

    test('keep the legacy heating energy codes as heating systems', () {
      // The heating_systems migration backfills one from the other.
      for (final energy in HeatingEnergy.values) {
        expect(parseDbEnum(HeatingSystem.values, energy.value), isNotNull);
      }
    });

    test('have distinct values', () {
      for (final values in <List<DbEnum>>[
        PropertyStatus.values,
        OwnershipType.values,
        SpecialSituation.values,
        PropertyType.values,
        SaleReason.values,
        PropertyLevels.values,
        WallMaterial.values,
        Adjacency.values,
        HeatingEnergy.values,
        HeatingSystem.values,
        Sanitation.values,
        OutdoorEquipment.values,
        MeasurementMethod.values,
        Overlooking.values,
        Provenance.values,
        RoomLevel.values,
        Glazing.values,
        LifestyleItemKind.values,
        LifestyleItemSource.values,
        DocumentKind.values,
        DocumentStatus.values,
      ]) {
        final stored = values.map((v) => v.value).toSet();
        expect(stored, hasLength(values.length));
        for (final value in values) {
          expect(parseDbEnum(values, value.value), value);
        }
      }
    });
  });
}
