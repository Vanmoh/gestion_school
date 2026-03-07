class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  static const String authBase = '/auth';
  static const String login = '$authBase/login/';
  static const String refresh = '$authBase/refresh/';
  static const String me = '$authBase/users/me/';
}
