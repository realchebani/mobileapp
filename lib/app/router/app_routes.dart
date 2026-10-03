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

  /// Seller space, tab "Mon bien": with one property, its home (draft:
  /// "Mon dossier vendeur", sent: V9 Dashboard); with several, "Mes biens".
  static const seller = '/vendeur';

  /// Tab "Visites" (V13, EPIC-09).
  static const sellerVisits = '/vendeur/visites';

  /// Tab "Coffre-fort" (C1, EPIC-11).
  static const sellerVault = '/vendeur/coffre';

  /// Tab "Compte" (C2).
  static const sellerAccount = '/vendeur/compte';

  /// V18 · Mes documents of the property [id] (EPIC-11), opened on the
  /// rubric [rubric] (`VaultRubric.code`) when given.
  static String sellerVaultProperty(String id, {String? rubric}) =>
      '$sellerVault/biens/$id${rubric == null ? '' : '?rubrique=$rubric'}';

  /// V18 · Mes documents of the sale lot [id] (EPIC-11).
  static String sellerVaultLot(String id) => '$sellerVault/lots/$id';

  /// V19 · Informations & sécurité (EPIC-11).
  static const sellerProfile = '/vendeur/compte/profil';

  /// Notifications, the full list (EPIC-11).
  static const sellerNotifications = '/vendeur/compte/notifications';

  /// Supprimer mon compte (EPIC-11), reachable from every space.
  static const accountDeletion = '/compte/suppression';

  /// Compte désactivé — réactiver (EPIC-11): where a deactivated account
  /// lands after signing in.
  static const accountDeactivated = '/compte/desactive';

  /// Properties of the seller live under this path (EPIC-13).
  static const sellerProperties = '/vendeur/biens';

  /// "Ajouter un bien" (EPIC-13).
  static const sellerNewProperty = '/vendeur/biens/nouveau';

  /// Sale lots live under this path (EPIC-13).
  static const sellerLots = '/vendeur/lots';

  /// Path segment of the seller tunnel steps, under a property.
  static const auditSegment = 'audit';

  /// Home of the property [id] (draft: start / resume the audit; sent:
  /// V9 Dashboard).
  static String sellerProperty(String id) => '$sellerProperties/$id';

  /// Step [segment] of the seller tunnel of the property [id] (see
  /// `SellerTunnelStep.location`).
  static String sellerPropertyAudit(String id, String segment) =>
      '$sellerProperties/$id/$auditSegment/$segment';

  /// V9b · Rapport d’avis de valeur of the property [id].
  static String sellerReport(String id) => '$sellerProperties/$id/rapport';

  /// V8b · Synthèse du marché (non-certified estimate, EPIC-05) of the
  /// property [id], pushed above the tabs.
  static String sellerMarket(String id) => '$sellerProperties/$id/marche';

  /// Sale lot [id] (EPIC-13).
  static String sellerLot(String id) => '$sellerLots/$id';

  /// Sales live under this path (EPIC-08).
  static const sellerSales = '/vendeur/ventes';

  /// A sale [id] (property or lot): the activation screen of its formula
  /// (V11 L’Essentiel, V11b Le Premium, V11c L’Expert).
  static String sellerSale(String id) => '$sellerSales/$id';

  /// V11a · Mise en ligne of the sale [id].
  static String sellerSaleListing(String id) => '$sellerSales/$id/annonce';

  /// Photos of the listing of the sale [id].
  static String sellerSaleListingPhotos(String id) =>
      '$sellerSales/$id/annonce/photos';

  /// Preview of the listing of the sale [id].
  static String sellerSaleListingPreview(String id) =>
      '$sellerSales/$id/annonce/apercu';

  /// Routes before EPIC-13 (one property per seller), still opened by old
  /// links: they redirect to the open (or only) property.
  static const legacySellerReport = '/vendeur/rapport';
  static const legacySellerMarket = '/vendeur/marche';
  static const legacySellerAudit = '/vendeur/audit';

  /// Buyer space (placeholder).
  static const buyer = '/acheteur';

  /// Design system gallery (development flavor only).
  static const designSystem = '/design-system';
}
