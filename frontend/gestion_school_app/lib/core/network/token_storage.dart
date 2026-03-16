import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'cached_user';
  static const _apiBaseUrlKey = 'api_base_url';

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<String?> accessToken() => _storage.read(key: _accessKey);
  Future<String?> refreshToken() => _storage.read(key: _refreshKey);
  Future<String?> cachedUser() => _storage.read(key: _userKey);
  Future<String?> apiBaseUrl() => _storage.read(key: _apiBaseUrlKey);

  Future<void> saveCachedUser(String userJson) async {
    await _storage.write(key: _userKey, value: userJson);
  }

  Future<void> saveApiBaseUrl(String url) async {
    await _storage.write(key: _apiBaseUrlKey, value: url);
  }

  Future<void> clearApiBaseUrl() async {
    await _storage.delete(key: _apiBaseUrlKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }
}
