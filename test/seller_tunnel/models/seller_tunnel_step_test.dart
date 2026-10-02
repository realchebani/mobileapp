import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

void main() {
  group(SellerTunnelStep, () {
    test('lists the V1 → V8 screens in order', () {
      expect(SellerTunnelStep.values.map((s) => s.number), [
        1, 2, 3, 4, 5, 5, 6, 7, 8, //
      ]);
      expect(SellerTunnelStep.values.map((s) => s.segment), [
        'proprietaires',
        'localisation',
        'contexte',
        'technique',
        'methode',
        'surfaces',
        'cadre-de-vie',
        'documents',
        'envoye',
      ]);
    });

    test('builds the route of a property', () {
      expect(
        SellerTunnelStep.technical.routeFor('p1'),
        '/vendeur/biens/p1/audit/technique',
      );
    });

    test('finds the step of a segment or a location', () {
      for (final step in SellerTunnelStep.values) {
        expect(SellerTunnelStep.fromSegment(step.segment), step);
        expect(SellerTunnelStep.fromLocation(step.routeFor('p1')), step);
      }
      expect(SellerTunnelStep.fromSegment('inconnu'), isNull);
      expect(SellerTunnelStep.fromLocation('/vendeur'), isNull);
      expect(SellerTunnelStep.fromLocation('/'), isNull);
      expect(
        SellerTunnelStep.fromLocation('/vendeur/biens/p1/rapport'),
        isNull,
      );
      expect(
        SellerTunnelStep.fromLocation(
          '/vendeur/biens/p1/audit/technique-vocal',
        ),
        isNull,
      );
    });

    test('has French labels', () {
      final l10n = AppLocalizationsFr();
      expect(SellerTunnelStep.values.map((s) => s.label(l10n)), [
        'Propriétaires',
        'Cadastre',
        'Contexte',
        'Technique',
        'Pièces',
        'Pièces',
        'Cadre de vie',
        'Documents',
        'Documents',
      ]);
    });
  });
}
