/// Paths of the app screens.
abstract final class AppRoutes {
  /// 00 · Splash, while the session and profile are restored.
  static const splash = '/splash';

  /// 00b · Découvrir (onboarding), until seen once.
  static const onboarding = '/decouvrir';

  /// 01 · Connexion.
  static const login = '/connexion';

  /// 01b · Connexion par e-mail.
  static const loginEmail = '/connexion/email';

  /// 01c · Vérifiez vos e-mails.
  static const checkInbox = '/connexion/verifier';

  /// 02 · Sélecteur de rôle.
  static const role = '/role';

  /// Seller space: entry screen of the seller dossier ("Mon dossier
  /// vendeur").
  static const seller = '/vendeur';

  /// Seller tunnel steps live under this path (see `SellerTunnelStep`).
  static const sellerAudit = '/vendeur/audit';

  /// V1 · Propriétaires.
  static const sellerOwners = '/vendeur/audit/proprietaires';

  /// V2 · Adresse & cadastre.
  static const sellerLocation = '/vendeur/audit/localisation';

  /// V3 · Contexte & type de bien.
  static const sellerContext = '/vendeur/audit/contexte';

  /// V4b · Audit technique (mode écran).
  static const sellerTechnical = '/vendeur/audit/technique';

  /// V5 · Méthode de relevé.
  static const sellerMethod = '/vendeur/audit/methode';

  /// V5c · Récapitulatif des surfaces.
  static const sellerSurfaces = '/vendeur/audit/surfaces';

  /// V6 · Cadre de vie.
  static const sellerLifestyle = '/vendeur/audit/cadre-de-vie';

  /// V7 · Coffre de documents.
  static const sellerDocuments = '/vendeur/audit/documents';

  /// V8 · Dossier envoyé, attente de l’expert.
  static const sellerSubmitted = '/vendeur/audit/envoye';

  /// Buyer space (placeholder).
  static const buyer = '/acheteur';

  /// Design system gallery (development flavor only).
  static const designSystem = '/design-system';
}
