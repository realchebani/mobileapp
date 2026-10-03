import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_space/sale/premium/diagnostics_rules.dart';
import 'package:mobileapp/seller_space/sale/premium/premium_view.dart';
import 'package:property_repository/property_repository.dart';
import 'package:sale_repository/sale_repository.dart';

void main() {
  Property house({int? year, List<HeatingSystem> heating = const []}) =>
      Property(
        id: 'p',
        ownerId: 'u',
        propertyType: PropertyType.house,
        constructionYear: year,
        heatingSystems: heating,
      );

  group('presetDiagnostics', () {
    test('recent house: DPE and ERP only', () {
      expect(presetDiagnostics([house(year: 2020)], year: 2026), {
        Diagnostic.risks: DiagnosticReason.always,
        Diagnostic.dpe: DiagnosticReason.always,
      });
    });

    test('1998 house with gas', () {
      final preset = presetDiagnostics([
        house(year: 1998, heating: [HeatingSystem.gas]),
      ], year: 2026);
      expect(
        preset.keys,
        containsAll([Diagnostic.electricity, Diagnostic.gas]),
      );
      expect(preset[Diagnostic.gas], DiagnosticReason.gasHeating);
      expect(preset.containsKey(Diagnostic.asbestos), isFalse);
    });

    test('old house: asbestos and lead; unknown year: electricity', () {
      final old = presetDiagnostics([house(year: 1930)], year: 2026);
      expect(old.keys, containsAll([Diagnostic.asbestos, Diagnostic.lead]));
      expect(old.containsKey(Diagnostic.termites), isFalse);
      final unknown = presetDiagnostics([house()], year: 2026);
      expect(unknown[Diagnostic.electricity], DiagnosticReason.unknownYear);
    });

    test('land and parking: ERP only', () {
      expect(
        presetDiagnostics(const [
          Property(id: 'l', ownerId: 'u', propertyType: PropertyType.land),
          Property(id: 'g', ownerId: 'u', propertyType: PropertyType.parking),
        ], year: 2026),
        {Diagnostic.risks: DiagnosticReason.always},
      );
    });
  });

  test('shootingSlots: next 3 working days at 10 h and 14 h', () {
    // Friday 2 October 2026.
    final slots = shootingSlots(DateTime(2026, 10, 2, 9));
    expect(slots, [
      DateTime(2026, 10, 5, 10),
      DateTime(2026, 10, 5, 14),
      DateTime(2026, 10, 6, 10),
      DateTime(2026, 10, 6, 14),
      DateTime(2026, 10, 7, 10),
      DateTime(2026, 10, 7, 14),
    ]);
  });
}
