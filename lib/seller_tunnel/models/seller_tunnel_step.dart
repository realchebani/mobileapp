import 'package:mobileapp/app/router/app_routes.dart';
import 'package:mobileapp/l10n/l10n.dart';

/// What the right side of the tunnel header shows for a step.
enum TunnelHeaderMode {
  /// "Écran" pill (keyboard icon).
  screen,

  /// "Vocal" pill (mic icon).
  voice,

  /// Step counter, e.g. "5/7".
  counter,

  /// Nothing.
  none,
}

/// The screens of the seller tunnel, in order.
///
/// [number] is the progress step (1–7) stored in
/// `properties.current_step`; V5 and V5c share step 5, and the submitted
/// screen (V8) is 8. The screens a property goes through depend on its type
/// (`PropertyTypeProfile`). Each screen lives at
/// `/vendeur/biens/<property id>/audit/<segment>` ([routeFor]).
enum SellerTunnelStep {
  /// V1 · Propriétaires.
  owners(1, 'proprietaires', TunnelHeaderMode.screen),

  /// V2 · Adresse & cadastre.
  location(2, 'localisation', TunnelHeaderMode.screen),

  /// V3 · Contexte & type de bien.
  context(3, 'contexte', TunnelHeaderMode.screen),

  /// V4b · Audit technique (mode écran).
  technical(4, 'technique', TunnelHeaderMode.screen),

  /// V5 · Méthode de relevé.
  method(5, 'methode', TunnelHeaderMode.counter),

  /// V5c · Récapitulatif des surfaces.
  surfaces(5, 'surfaces', TunnelHeaderMode.counter),

  /// V6 · Cadre de vie.
  lifestyle(6, 'cadre-de-vie', TunnelHeaderMode.voice),

  /// V7 · Documents.
  documents(7, 'documents', TunnelHeaderMode.counter),

  /// V8 · Dossier envoyé (no header).
  submitted(8, 'envoye', TunnelHeaderMode.none);

  new(this.number, this.segment, this.headerMode);

  /// Number of progress steps of the full tunnel (V1 → V7).
  static const count = 7;

  /// Last path segment of the V4 voice audit (voice mode of V4b).
  static const voiceAuditSegment = 'technique-vocal';

  /// Progress step (1–7), 8 for [submitted].
  final int number;

  /// Last segment of the route of the screen.
  final String segment;

  /// Right side of the header.
  final TunnelHeaderMode headerMode;

  /// Route of the screen for the property [propertyId].
  String routeFor(String propertyId) =>
      AppRoutes.sellerPropertyAudit(propertyId, segment);

  /// The step whose screen has the last segment [segment], or null.
  static SellerTunnelStep? fromSegment(String segment) {
    for (final step in values) {
      if (step.segment == segment) return step;
    }
    return null;
  }

  /// The step whose screen is at [routeFor] (any property), or null.
  static SellerTunnelStep? fromLocation(String location) {
    final segments = Uri.parse(location).pathSegments;
    final audit = segments.length - 2;
    if (audit < 0 || segments[audit] != AppRoutes.auditSegment) return null;
    return fromSegment(segments.last);
  }

  /// Name shown in the header caption (`Étape N · <name>`).
  String label(AppLocalizations l10n) => switch (this) {
    owners => l10n.tunnelStepOwners,
    location => l10n.tunnelStepLocation,
    context => l10n.tunnelStepContext,
    technical => l10n.tunnelStepTechnical,
    method || surfaces => l10n.tunnelStepRooms,
    lifestyle => l10n.tunnelStepLifestyle,
    documents || submitted => l10n.tunnelStepDocuments,
  };
}
