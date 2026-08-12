class ApiConstants {
  static const String _urlCompilee = String.fromEnvironment('API_BASE_URL');
  static const String _portApi = String.fromEnvironment(
    'API_PORT',
    defaultValue: '8000',
  );

  /// Racine de l'API.
  ///
  /// Figee a la compilation, elle cassait a chaque changement de reseau: le
  /// build portait une adresse IP qui n'existait plus, et l'application ne
  /// joignait plus rien sans qu'aucun message ne dise pourquoi.
  ///
  /// Sur le web, l'adresse se deduit donc de la page servie: l'API repond sur
  /// le meme hote, a un autre port. Ouvrir l'application depuis n'importe
  /// quelle machine du reseau la fait pointer au bon endroit, sans
  /// recompiler. `--dart-define=API_BASE_URL=...` reste prioritaire pour les
  /// deploiements ou l'API vit ailleurs, comme en production.
  static String get baseUrl {
    if (_urlCompilee.isNotEmpty) return _urlCompilee;

    final page = Uri.base;
    if (page.host.isNotEmpty && page.scheme.startsWith('http')) {
      return '${page.scheme}://${page.host}:$_portApi/api';
    }
    return 'http://localhost:$_portApi/api';
  }

  static const String authBase = '/auth';
  static const String login = '$authBase/login/';
  static const String refresh = '$authBase/refresh/';
  static const String logout = '$authBase/logout/';
  static const String me = '$authBase/users/me/';
  static const String permissions = '$authBase/permissions/';
}
