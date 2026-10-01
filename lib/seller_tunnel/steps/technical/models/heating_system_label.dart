import 'package:mobileapp/l10n/l10n.dart';
import 'package:property_repository/property_repository.dart';

/// Label of a V4b heating system (chips of V4b, summary of V8).
String heatingSystemLabel(AppLocalizations l10n, HeatingSystem value) =>
    switch (value) {
      HeatingSystem.electricity => l10n.technicalHeatingElectricity,
      HeatingSystem.heatPump => l10n.technicalHeatingHeatPump,
      HeatingSystem.gas => l10n.technicalHeatingGas,
      HeatingSystem.fuelOil => l10n.technicalHeatingFuelOil,
      HeatingSystem.wood => l10n.technicalHeatingWood,
      HeatingSystem.pellets => l10n.technicalHeatingPellets,
      HeatingSystem.fireplace => l10n.technicalHeatingFireplace,
      HeatingSystem.districtHeating => l10n.technicalHeatingDistrict,
      HeatingSystem.solar => l10n.technicalHeatingSolar,
      HeatingSystem.other => l10n.technicalHeatingOther,
    };
