import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/app/app.dart';
import 'package:mobileapp/l10n/gen/app_localizations_fr.dart';
import 'package:mobileapp/seller_tunnel/seller_tunnel.dart';

void main() {
  group(SellerTunnelStep, () {
    test('lists the V1 → V8 screens in order', () {
      expect(SellerTunnelStep.values.map((s) => s.number), [
        1, 2, 3, 4, 5, 5, 6, 7, 8, //
      ]);
      expect(SellerTunnelStep.values.map((s) => s.path), [
        AppRoutes.sellerOwners,
        AppRoutes.sellerLocation,
        AppRoutes.sellerContext,
        AppRoutes.sellerTechnical,
        AppRoutes.sellerMethod,
        AppRoutes.sellerSurfaces,
        AppRoutes.sellerLifestyle,
        AppRoutes.sellerDocuments,
        AppRoutes.sellerSubmitted,
      ]);
      for (final step in SellerTunnelStep.values) {
        expect(step.path, startsWith('${AppRoutes.sellerAudit}/'));
      }
    });

    test('resumes at the first screen of a step', () {
      expect(SellerTunnelStep.resumeAt(0), SellerTunnelStep.owners);
      expect(SellerTunnelStep.resumeAt(1), SellerTunnelStep.owners);
      expect(SellerTunnelStep.resumeAt(4), SellerTunnelStep.technical);
      expect(SellerTunnelStep.resumeAt(5), SellerTunnelStep.method);
      expect(SellerTunnelStep.resumeAt(6), SellerTunnelStep.lifestyle);
      expect(SellerTunnelStep.resumeAt(8), SellerTunnelStep.submitted);
      expect(SellerTunnelStep.resumeAt(99), SellerTunnelStep.submitted);
    });

    test('links the screens', () {
      expect(SellerTunnelStep.owners.previous, isNull);
      expect(SellerTunnelStep.owners.next, SellerTunnelStep.location);
      expect(SellerTunnelStep.surfaces.previous, SellerTunnelStep.method);
      expect(SellerTunnelStep.documents.next, SellerTunnelStep.submitted);
      expect(SellerTunnelStep.submitted.next, SellerTunnelStep.submitted);
      expect(SellerTunnelStep.submitted.previous, isNull);
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
