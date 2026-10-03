import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

/// Why a diagnostic is preselected (shown to the seller).
enum DiagnosticReason { always, constructionYear, unknownYear, gasHeating }

/// The preselection of the mandatory diagnostics (V11b, plan §4.4, neutral
/// wording « Présélection d’après votre audit », no AI): explicit rules on
/// the dossier of the [members] sold, at [year].
///
/// - DPE and État des risques (ERP): always (ERP only for land / parking);
/// - Électricité: installation probably over 15 years (construction year
///   over 15 years ago, or unknown);
/// - Gaz: gas heating and the same age rule;
/// - Amiante: building permit before July 1997 (built before 1997);
/// - Plomb: built before 1949;
/// - Termites: depends on the town (prefectural order): never
///   preselected, the seller checks.
Map<Diagnostic, DiagnosticReason> presetDiagnostics(
  List<Property> members, {
  required int year,
}) {
  final preset = <Diagnostic, DiagnosticReason>{
    Diagnostic.risks: DiagnosticReason.always,
  };
  for (final member in members) {
    final type = member.propertyType;
    if (type == PropertyType.land || type == PropertyType.parking) continue;
    preset[Diagnostic.dpe] = DiagnosticReason.always;
    final built = member.constructionYear;
    final old = built == null || built < year - 15;
    final ageReason = built == null
        ? DiagnosticReason.unknownYear
        : DiagnosticReason.constructionYear;
    if (old) preset.putIfAbsent(Diagnostic.electricity, () => ageReason);
    if (old && member.heatingSystems.contains(HeatingSystem.gas)) {
      preset.putIfAbsent(Diagnostic.gas, () => DiagnosticReason.gasHeating);
    }
    if (built != null && built < 1997) {
      preset.putIfAbsent(
        Diagnostic.asbestos,
        () => DiagnosticReason.constructionYear,
      );
    }
    if (built != null && built < 1949) {
      preset.putIfAbsent(
        Diagnostic.lead,
        () => DiagnosticReason.constructionYear,
      );
    }
  }
  return preset;
}
