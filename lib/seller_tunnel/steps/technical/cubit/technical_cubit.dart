import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:mobileapp/seller_tunnel/steps/technical/models/technical_options.dart';
import 'package:property_repository/property_repository.dart';

part 'technical_state.dart';

/// Form of V4b · Audit technique (mode écran).
///
/// [submit] validates the answers; when they are valid it increments
/// `TechnicalState.saveRequests`, on which the view hands
/// `TechnicalState.patch` to the tunnel cubit (the step has no child rows).
class TechnicalCubit extends Cubit<TechnicalState> {
  new({required Property property, DateTime? today})
    : super(TechnicalState.fromProperty(property, today ?? DateTime.now()));

  void constructionYearChanged(String value) =>
      emit(state.copyWith(constructionYear: value));

  /// Picks [value], or clears the answer ("Non précisé") when null.
  void exposureChanged(Exposure? value) =>
      emit(state.copyWith(exposure: () => value));

  void livingAreaChanged(String value) =>
      emit(state.copyWith(livingArea: value));

  void livingRoomAreaChanged(String value) =>
      emit(state.copyWith(livingRoomArea: value));

  /// Changes the number of rooms; bedrooms never exceed it.
  void roomsChanged(int value) {
    final rooms = value.clamp(TechnicalState.minRooms, TechnicalState.maxRooms);
    emit(
      state.copyWith(
        rooms: rooms,
        bedrooms: state.bedrooms > rooms ? rooms : null,
      ),
    );
  }

  void bedroomsChanged(int value) =>
      emit(state.copyWith(bedrooms: value.clamp(0, state.rooms)));

  void levelsChanged(PropertyLevels value) =>
      emit(state.copyWith(levels: value));

  /// Selects [value], or clears it when it was selected (optional answer).
  void wallMaterialToggled(WallMaterial value) => emit(
    state.copyWith(
      wallMaterial: () => state.wallMaterial == value ? null : value,
    ),
  );

  /// Selects [value], or clears it when it was selected (optional answer).
  void adjacencyToggled(Adjacency value) => emit(
    state.copyWith(adjacency: () => state.adjacency == value ? null : value),
  );

  /// Picks [value], or clears the answer ("Non précisé") when null.
  void roofTypeChanged(RoofType? value) =>
      emit(state.copyWith(roofType: () => value));

  void roofYearChanged(String value) => emit(state.copyWith(roofYear: value));

  /// Selects the main energy (required: tapping it again keeps it).
  void heatingEnergyChanged(HeatingEnergy value) =>
      emit(state.copyWith(heatingEnergy: value));

  /// Picks [value], or clears the answer ("Non précisé") when null.
  void heatPumpTypeChanged(HeatPumpType? value) =>
      emit(state.copyWith(heatPumpType: () => value));

  void heatPumpYearChanged(String value) =>
      emit(state.copyWith(heatPumpYear: value));

  /// Selects [value], or clears it when it was selected (optional answer).
  void sanitationToggled(Sanitation value) => emit(
    state.copyWith(sanitation: () => state.sanitation == value ? null : value),
  );

  /// Adds or removes [value] (multiple choice, kept in the design order).
  void outdoorEquipmentToggled(OutdoorEquipment value) {
    final selected = state.outdoorEquipment.contains(value);
    emit(
      state.copyWith(
        outdoorEquipment: [
          for (final item in OutdoorEquipment.values)
            if (item == value
                ? !selected
                : state.outdoorEquipment.contains(item))
              item,
        ],
      ),
    );
  }

  /// Picks [value], or clears the answer ("Non précisé") when null.
  void poolTypeChanged(PoolType? value) =>
      emit(state.copyWith(poolType: () => value));

  void poolDimensionsChanged(String value) =>
      emit(state.copyWith(poolDimensions: value));

  /// "Enregistrer et continuer": requests the save, or shows the errors.
  void submit() {
    if (!state.isValid) {
      emit(
        state.copyWith(
          showErrors: true,
          submitAttempts: state.submitAttempts + 1,
        ),
      );
      return;
    }
    emit(
      state.copyWith(showErrors: true, saveRequests: state.saveRequests + 1),
    );
  }
}
