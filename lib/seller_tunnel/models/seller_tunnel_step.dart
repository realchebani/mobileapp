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
/// [number] is the progress step (1–7) shown in the header and stored in
/// `properties.current_step`; V5 and V5c share step 5, and the submitted
/// screen (V8) is 8.
enum SellerTunnelStep {
  /// V1 · Propriétaires.
  owners(1, AppRoutes.sellerOwners, TunnelHeaderMode.screen),

  /// V2 · Adresse & cadastre.
  location(2, AppRoutes.sellerLocation, TunnelHeaderMode.screen),

  /// V3 · Contexte & type de bien.
  context(3, AppRoutes.sellerContext, TunnelHeaderMode.screen),

  /// V4b · Audit technique (mode écran).
  technical(4, AppRoutes.sellerTechnical, TunnelHeaderMode.screen),

  /// V5 · Méthode de relevé.
  method(5, AppRoutes.sellerMethod, TunnelHeaderMode.counter),

  /// V5c · Récapitulatif des surfaces.
  surfaces(5, AppRoutes.sellerSurfaces, TunnelHeaderMode.counter),

  /// V6 · Cadre de vie.
  lifestyle(6, AppRoutes.sellerLifestyle, TunnelHeaderMode.voice),

  /// V7 · Documents.
  documents(7, AppRoutes.sellerDocuments, TunnelHeaderMode.counter),

  /// V8 · Dossier envoyé (no header).
  submitted(8, AppRoutes.sellerSubmitted, TunnelHeaderMode.none);

  new(this.number, this.path, this.headerMode);

  /// Number of progress steps (V1 → V7).
  static const count = 7;

  /// Progress step (1–7), 8 for [submitted].
  final int number;

  /// Route of the screen.
  final String path;

  /// Right side of the header.
  final TunnelHeaderMode headerMode;

  /// The screen where a dossier whose `current_step` is [currentStep]
  /// resumes: the first screen of that step.
  static SellerTunnelStep resumeAt(int currentStep) {
    for (final step in values) {
      if (step.number >= currentStep) return step;
    }
    return submitted;
  }

  /// The following screen ([submitted] after [documents] and itself).
  SellerTunnelStep get next =>
      this == submitted ? submitted : values[index + 1];

  /// The previous screen, or `null` for the first one and [submitted]
  /// (back then goes to the seller space).
  SellerTunnelStep? get previous =>
      this == owners || this == submitted ? null : values[index - 1];

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
