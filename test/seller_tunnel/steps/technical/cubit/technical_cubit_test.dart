import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/cubit/technical_cubit.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/models/technical_options.dart';
import 'package:property_repository/property_repository.dart';

final _today = DateTime(2026, 10);

const _house = Property(
  id: 'p',
  ownerId: 'u',
  propertyType: PropertyType.house,
);

const _filled = Property(
  id: 'p',
  ownerId: 'u',
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
  heatingEnergy: HeatingEnergy.heatPump,
  heatPumpType: 'air_eau',
  heatPumpYear: 2021,
  sanitation: Sanitation.mainsSewer,
  outdoorEquipment: [OutdoorEquipment.pool, OutdoorEquipment.garage],
  poolType: 'enterree_liner',
  poolLengthM: 8,
  poolWidthM: 4.25,
  provenance: {'heat_pump_year': 'document', 'roof_year': 'declared'},
);

TechnicalState _state(Property property) =>
    TechnicalState.fromProperty(property, _today);

TechnicalCubit _cubit([Property property = _house]) =>
    TechnicalCubit(property: property, today: _today);

void main() {
  group(TechnicalState, () {
    test('loads the saved answers', () {
      final state = _state(_filled);
      expect(state.constructionYear, '1998');
      expect(state.exposure, Exposure.south);
      expect(state.livingArea, '115');
      expect(state.livingRoomArea, '38,5');
      expect(state.rooms, 5);
      expect(state.bedrooms, 3);
      expect(state.roofType, RoofType.tiles);
      expect(state.heatPumpType, HeatPumpType.airToWater);
      expect(state.poolType, PoolType.inGroundLiner);
      expect(state.poolDimensions, '8 × 4,25');
      expect(state.isValid, isTrue);
    });

    test('defaults to 1 room and no bedroom, clamping saved counts', () {
      expect(_state(_house).rooms, 1);
      expect(_state(_house).bedrooms, 0);
      final clamped = _state(
        const Property(
          id: 'p',
          ownerId: 'u',
          roomsCount: 50,
          bedroomsCount: 60,
        ),
      );
      expect(clamped.rooms, 30);
      expect(clamped.bedrooms, 30);
    });

    test('keeps no dimensions when a side is missing', () {
      expect(
        _state(const Property(id: 'p', ownerId: 'u', poolLengthM: 8))
            .poolDimensions,
        '',
      );
    });

    test('adapts the questions to the property type', () {
      final house = _state(_house);
      expect(house.asksBuilding, isTrue);
      expect(house.asksWholeBuilding, isTrue);
      expect(house.requiresLevels, isTrue);

      final apartment = _state(
        const Property(
          id: 'p',
          ownerId: 'u',
          propertyType: PropertyType.apartment,
        ),
      );
      expect(apartment.asksBuilding, isTrue);
      expect(apartment.asksWholeBuilding, isFalse);
      expect(apartment.levelsError, isNull);

      final other = _state(const Property(id: 'p', ownerId: 'u'));
      expect(other.asksWholeBuilding, isTrue);
      expect(other.levelsError, isNull);

      final land = _state(
        const Property(id: 'p', ownerId: 'u', propertyType: PropertyType.land),
      );
      expect(land.asksBuilding, isFalse);
      expect(land.isValid, isTrue);
      expect(land.values[PropertyColumns.constructionYear], isNull);
      expect(land.values[PropertyColumns.roomsCount], isNull);
    });

    test('requires the year, the area, the levels and the energy', () {
      final state = _state(_house);
      expect(state.constructionYearError, TechnicalError.required);
      expect(state.livingAreaError, TechnicalError.required);
      expect(state.livingRoomAreaError, isNull);
      expect(state.levelsError, TechnicalError.required);
      expect(state.heatingEnergyError, TechnicalError.required);
      expect(state.roofYearError, isNull);
      expect(state.heatPumpYearError, isNull);
      expect(state.poolDimensionsError, isNull);
      expect(state.isValid, isFalse);
    });

    test('checks the ranges', () {
      final state = _state(_filled).copyWith(
        constructionYear: '1500',
        livingArea: '4',
        livingRoomArea: '0,5',
        roofYear: '2030',
        heatPumpYear: '1800',
        poolDimensions: '8',
      );
      expect(state.constructionYearError, TechnicalError.yearRange);
      expect(state.livingAreaError, TechnicalError.areaRange);
      expect(state.livingRoomAreaError, TechnicalError.areaRange);
      expect(state.roofMinYear, TechnicalState.minConstructionYear);
      expect(state.roofYearError, TechnicalError.yearRange);
      expect(state.heatPumpYearError, TechnicalError.yearRange);
      expect(state.poolDimensionsError, TechnicalError.dimensions);
    });

    test('rejects incomplete years and areas', () {
      final state = _state(_filled).copyWith(
        constructionYear: '98',
        livingArea: ',',
        livingRoomArea: ',',
        roofYear: '20',
        heatPumpYear: '1',
      );
      expect(state.constructionYearError, TechnicalError.yearRange);
      expect(state.livingAreaError, TechnicalError.areaRange);
      expect(state.livingRoomAreaError, TechnicalError.areaRange);
      expect(state.roofYearError, TechnicalError.yearRange);
      expect(state.heatPumpYearError, TechnicalError.yearRange);
    });

    test('records no provenance for cleared answers', () {
      final state = _state(_filled).copyWith(heatingEnergy: HeatingEnergy.gas);
      expect(state.isChanged(PropertyColumns.heatPumpYear), isTrue);
      expect(state.patch[PropertyColumns.provenance], {
        'heat_pump_year': 'document',
        'roof_year': 'declared',
        'heating_energy': 'declared',
      });
    });

    test('keeps the roof after the construction', () {
      final state = _state(_filled).copyWith(roofYear: '1990');
      expect(state.roofMinYear, 1998);
      expect(state.roofYearError, TechnicalError.yearRange);
    });

    test('keeps the living room within the living area', () {
      final state = _state(_filled).copyWith(livingRoomArea: '120');
      expect(state.livingRoomAreaError, TechnicalError.livingRoomTooLarge);
      expect(state.copyWith(livingArea: '').livingRoomAreaError, isNull);
    });

    test('parses the typed values', () {
      expect(TechnicalState.parseYear(' 1998 '), 1998);
      expect(TechnicalState.parseYear('98'), isNull);
      expect(TechnicalState.parseDecimal('38,5'), 38.5);
      expect(TechnicalState.parseDecimal('1 200.25'), 1200.25);
      expect(TechnicalState.parseDecimal('3,456'), isNull);
      expect(TechnicalState.parseDecimal('38,'), 38);
      expect(TechnicalState.parseDecimal(',5'), 0.5);
      expect(TechnicalState.parseDecimal(','), isNull);
      expect(TechnicalState.parseDimensions('8 × 4'), (8.0, 4.0));
      expect(TechnicalState.parseDimensions('10,5x5.5'), (10.5, 5.5));
      expect(TechnicalState.parseDimensions('0 × 4'), isNull);
      expect(TechnicalState.parseDimensions('8 × 1000'), isNull);
      expect(TechnicalState.formatDecimal(null), '');
      expect(TechnicalState.formatDecimal(38.50), '38,5');
      expect(TechnicalState.formatDecimal(115), '115');
    });

    test('marks edited answers as declared in the patch', () {
      final unchanged = _state(_filled);
      expect(unchanged.isChanged(PropertyColumns.outdoorEquipment), isFalse);
      expect(
        unchanged.provenanceOf(PropertyColumns.heatPumpYear),
        Provenance.document,
      );
      expect(unchanged.patch.containsKey(PropertyColumns.provenance), isFalse);

      final edited = unchanged.copyWith(
        heatPumpYear: '2022',
        outdoorEquipment: [OutdoorEquipment.pool],
      );
      expect(
        edited.provenanceOf(PropertyColumns.heatPumpYear),
        Provenance.declared,
      );
      expect(edited.isChanged(PropertyColumns.outdoorEquipment), isTrue);
      expect(
        unchanged
            .copyWith(
              outdoorEquipment: [
                OutdoorEquipment.pool,
                OutdoorEquipment.terrace,
              ],
            )
            .isChanged(PropertyColumns.outdoorEquipment),
        isTrue,
      );
      expect(edited.patch, {
        ...edited.values,
        PropertyColumns.provenance: {
          'heat_pump_year': 'declared',
          'roof_year': 'declared',
          'outdoor_equipment': 'declared',
        },
      });
    });

    test('clears the answers of hidden questions', () {
      final state = _state(_filled).copyWith(
        heatingEnergy: HeatingEnergy.gas,
        outdoorEquipment: [OutdoorEquipment.garage],
      );
      expect(state.values[PropertyColumns.heatPumpType], isNull);
      expect(state.values[PropertyColumns.heatPumpYear], isNull);
      expect(state.values[PropertyColumns.poolType], isNull);
      expect(state.values[PropertyColumns.poolLengthM], isNull);
      expect(state.values[PropertyColumns.poolWidthM], isNull);
      expect(_state(_filled).values, {
        PropertyColumns.constructionYear: 1998,
        PropertyColumns.orientation: Exposure.south,
        PropertyColumns.livingAreaM2: 115.0,
        PropertyColumns.livingRoomAreaM2: 38.5,
        PropertyColumns.roomsCount: 5,
        PropertyColumns.bedroomsCount: 3,
        PropertyColumns.levels: PropertyLevels.oneUpperFloor,
        PropertyColumns.wallMaterial: WallMaterial.concreteBlock,
        PropertyColumns.adjacency: Adjacency.detached,
        PropertyColumns.roofType: RoofType.tiles,
        PropertyColumns.roofYear: 2016,
        PropertyColumns.heatingEnergy: HeatingEnergy.heatPump,
        PropertyColumns.heatPumpType: HeatPumpType.airToWater,
        PropertyColumns.heatPumpYear: 2021,
        PropertyColumns.sanitation: Sanitation.mainsSewer,
        PropertyColumns.outdoorEquipment: [
          OutdoorEquipment.pool,
          OutdoorEquipment.garage,
        ],
        PropertyColumns.poolType: PoolType.inGroundLiner,
        PropertyColumns.poolLengthM: 8.0,
        PropertyColumns.poolWidthM: 4.25,
      });
    });
  });

  group(TechnicalCubit, () {
    test('starts today by default', () {
      expect(
        TechnicalCubit(property: _house).state.today.year,
        DateTime.now().year,
      );
    });

    blocTest<TechnicalCubit, TechnicalState>(
      'edits the answers',
      build: _cubit,
      act: (cubit) => cubit
        ..constructionYearChanged('1998')
        ..exposureChanged(Exposure.south)
        ..livingAreaChanged('115')
        ..livingRoomAreaChanged('38,5')
        ..levelsChanged(PropertyLevels.singleStorey)
        ..roofTypeChanged(RoofType.slate)
        ..roofYearChanged('2016')
        ..heatingEnergyChanged(HeatingEnergy.heatPump)
        ..heatPumpTypeChanged(HeatPumpType.geothermal)
        ..heatPumpYearChanged('2021')
        ..poolTypeChanged(PoolType.aboveGround)
        ..poolDimensionsChanged('8 × 4')
        ..exposureChanged(null),
      verify: (cubit) {
        final state = cubit.state;
        expect(state.constructionYear, '1998');
        expect(state.exposure, isNull);
        expect(state.livingArea, '115');
        expect(state.livingRoomArea, '38,5');
        expect(state.levels, PropertyLevels.singleStorey);
        expect(state.roofType, RoofType.slate);
        expect(state.roofYear, '2016');
        expect(state.heatingEnergy, HeatingEnergy.heatPump);
        expect(state.heatPumpType, HeatPumpType.geothermal);
        expect(state.heatPumpYear, '2021');
        expect(state.poolType, PoolType.aboveGround);
        expect(state.poolDimensions, '8 × 4');
      },
    );

    blocTest<TechnicalCubit, TechnicalState>(
      'keeps bedrooms within rooms',
      build: _cubit,
      act: (cubit) => cubit
        ..roomsChanged(4)
        ..bedroomsChanged(9)
        ..roomsChanged(2)
        ..roomsChanged(0),
      verify: (cubit) {
        expect(cubit.state.rooms, 1);
        expect(cubit.state.bedrooms, 1);
      },
    );

    test('toggles the optional single choices', () {
      final cubit = _cubit()
        ..wallMaterialToggled(WallMaterial.stone)
        ..adjacencyToggled(Adjacency.oneSide)
        ..sanitationToggled(Sanitation.septicTank);
      expect(cubit.state.wallMaterial, WallMaterial.stone);
      expect(cubit.state.adjacency, Adjacency.oneSide);
      expect(cubit.state.sanitation, Sanitation.septicTank);
      cubit
        ..wallMaterialToggled(WallMaterial.stone)
        ..adjacencyToggled(Adjacency.oneSide)
        ..sanitationToggled(Sanitation.septicTank);
      expect(cubit.state.wallMaterial, isNull);
      expect(cubit.state.adjacency, isNull);
      expect(cubit.state.sanitation, isNull);
    });

    blocTest<TechnicalCubit, TechnicalState>(
      'toggles the outdoor equipment in the design order',
      build: _cubit,
      act: (cubit) => cubit
        ..outdoorEquipmentToggled(OutdoorEquipment.terrace)
        ..outdoorEquipmentToggled(OutdoorEquipment.pool)
        ..outdoorEquipmentToggled(OutdoorEquipment.garage)
        ..outdoorEquipmentToggled(OutdoorEquipment.terrace),
      verify: (cubit) => expect(cubit.state.outdoorEquipment, [
        OutdoorEquipment.pool,
        OutdoorEquipment.garage,
      ]),
    );

    blocTest<TechnicalCubit, TechnicalState>(
      'shows the errors of an invalid submission',
      build: _cubit,
      act: (cubit) => cubit.submit(),
      verify: (cubit) {
        expect(cubit.state.showErrors, isTrue);
        expect(cubit.state.submitAttempts, 1);
        expect(cubit.state.saveRequests, 0);
      },
    );

    blocTest<TechnicalCubit, TechnicalState>(
      'requests the save of a valid submission',
      build: () => _cubit(_filled),
      act: (cubit) => cubit.submit(),
      verify: (cubit) {
        expect(cubit.state.submitAttempts, 0);
        expect(cubit.state.saveRequests, 1);
      },
    );
  });
}
