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

  /// Seller space (placeholder until V1).
  static const seller = '/vendeur';

  /// Buyer space (placeholder).
  static const buyer = '/acheteur';

  /// Design system gallery (development flavor only).
  static const designSystem = '/design-system';
}
