/// Paths of the back-office.
abstract final class BoRoutes {
  static const loading = '/chargement';
  static const login = '/connexion';
  static const mfa = '/double-authentification';
  static const denied = '/acces-refuse';
  static const failed = '/indisponible';
  static const queue = '/dossiers';
  static const team = '/equipe';
  static const audit = '/journal';

  static String dossier(String id, [String? tab]) =>
      tab == null ? '$queue/$id' : '$queue/$id/$tab';
}
