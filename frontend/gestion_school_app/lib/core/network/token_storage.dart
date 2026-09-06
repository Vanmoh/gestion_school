import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static final Map<String, String> _fallbackMemory = <String, String>{};
  static final Map<String, String?> _memoryCache = <String, String?>{};
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'cached_user';
  static const _apiBaseUrlKey = 'api_base_url';
  static const _selectedEtablissementKey = 'selected_etablissement';
  // L'annee de travail voyage comme l'etablissement: choisie une fois,
  // portee par toutes les requetes. Chaque ecran gerait la sienne avant,
  // avec des selecteurs qui ne s'accordaient jamais.
  static const _selectedAcademicYearKey = 'selected_academic_year';
  static const _reminderHistoryKey = 'finance_reminder_history';

  /// Vide les caches memoire.
  ///
  /// Ils sont statiques: une valeur lue une fois vaut pour tout le processus,
  /// ce qui est voulu en production -- le stockage securise echoue sur
  /// certaines plateformes, et cette memoire est le filet.
  ///
  /// En test, tous les cas d'un meme fichier partagent le processus: sans
  /// cette purge, le premier etablissement lu s'impose a tous les cas
  /// suivants, quel que soit le stockage simule qu'ils installent. Un test
  /// passait alors seul et echouait en groupe, ce qui est la pire facon de
  /// s'en apercevoir.
  @visibleForTesting
  static void purgerCacheMemoire() {
    _memoryCache.clear();
    _fallbackMemory.clear();
  }

  Future<void> _safeWrite(String key, String value) async {
    _memoryCache[key] = value;
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      _fallbackMemory[key] = value;
    }
  }

  Future<String?> _safeRead(String key) async {
    if (_memoryCache.containsKey(key)) {
      return _memoryCache[key];
    }

    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        _memoryCache[key] = value;
        return value;
      }
    } catch (_) {
      // Fallback below.
    }
    final fallback = _fallbackMemory[key];
    _memoryCache[key] = fallback;
    return fallback;
  }

  Future<void> _safeDelete(String key) async {
    _memoryCache.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Fallback below.
    }
    _fallbackMemory.remove(key);
  }

  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await _safeWrite(_accessKey, access);
    await _safeWrite(_refreshKey, refresh);
  }

  Future<String?> accessToken() => _safeRead(_accessKey);
  Future<String?> refreshToken() => _safeRead(_refreshKey);
  Future<String?> cachedUser() => _safeRead(_userKey);
  Future<String?> apiBaseUrl() => _safeRead(_apiBaseUrlKey);
  Future<String?> selectedEtablissement() =>
      _safeRead(_selectedEtablissementKey);
  Future<String?> selectedAcademicYear() =>
      _safeRead(_selectedAcademicYearKey);
  Future<String?> reminderHistory() => _safeRead(_reminderHistoryKey);

  Future<void> saveCachedUser(String userJson) async {
    await _safeWrite(_userKey, userJson);
  }

  Future<void> saveApiBaseUrl(String url) async {
    await _safeWrite(_apiBaseUrlKey, url);
  }

  Future<void> saveSelectedEtablissement(String value) async {
    await _safeWrite(_selectedEtablissementKey, value);
  }

  Future<void> saveSelectedAcademicYear(String value) async {
    await _safeWrite(_selectedAcademicYearKey, value);
  }

  Future<void> saveReminderHistory(String value) async {
    await _safeWrite(_reminderHistoryKey, value);
  }

  Future<void> clearApiBaseUrl() async {
    await _safeDelete(_apiBaseUrlKey);
  }

  Future<void> clearSelectedEtablissement() async {
    await _safeDelete(_selectedEtablissementKey);
  }

  Future<void> clearSelectedAcademicYear() async {
    await _safeDelete(_selectedAcademicYearKey);
  }

  Future<void> clearReminderHistory() async {
    await _safeDelete(_reminderHistoryKey);
  }

  Future<void> clear() async {
    await _safeDelete(_accessKey);
    await _safeDelete(_refreshKey);
    await _safeDelete(_userKey);
  }
}
