import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

bool _isTransientNetworkError(DioException error) {
  return error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError;
}

bool _isIdempotentMethod(String method) {
  final normalized = method.toUpperCase();
  return normalized == 'GET' || normalized == 'HEAD' || normalized == 'OPTIONS';
}

<<<<<<< HEAD
=======
bool _sameBaseUrl(String left, String right) {
  final l = left.trim().replaceAll(RegExp(r'/+$'), '');
  final r = right.trim().replaceAll(RegExp(r'/+$'), '');
  return l == r;
}

>>>>>>> main
final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.read(tokenStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 45),
<<<<<<< HEAD
      headers: {'Content-Type': 'application/json'},
=======
>>>>>>> main
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.data is FormData) {
          options.contentType = Headers.multipartFormDataContentType;
        }

        final values = await Future.wait<String?>([
          tokenStorage.apiBaseUrl(),
          tokenStorage.accessToken(),
          tokenStorage.selectedEtablissement(),
          tokenStorage.cachedUser(),
        ]);

        final storedBaseUrl = values[0];
        final effectiveBaseUrl =
            (storedBaseUrl != null && storedBaseUrl.isNotEmpty)
            ? storedBaseUrl
            : ApiConstants.baseUrl;
        options.baseUrl = effectiveBaseUrl;
        options.extra['effective_base_url'] = effectiveBaseUrl;
        options.extra['had_custom_base_url'] =
            storedBaseUrl != null && storedBaseUrl.isNotEmpty;

        final token = values[1];
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        final selectedEtablissementRaw = values[2];
        final cachedUserRaw = values[3];

        String? role;
        int? userEtablissementId;
        String? userEtablissementName;
        if (cachedUserRaw != null && cachedUserRaw.isNotEmpty) {
          try {
            final decoded = jsonDecode(cachedUserRaw) as Map<String, dynamic>;
            role = decoded['role']?.toString();
            userEtablissementId = (decoded['etablissementId'] as num?)?.toInt();
            userEtablissementName = decoded['etablissementName']?.toString();
          } catch (_) {
            // Ignore malformed cached user payload.
          }
        }

        if (selectedEtablissementRaw != null &&
          selectedEtablissementRaw.isNotEmpty) {
          try {
            final decoded =
                jsonDecode(selectedEtablissementRaw) as Map<String, dynamic>;
            final etablissementId = decoded['id'];
            final etablissementName = decoded['name']?.toString().trim();
            if (etablissementId != null) {
              options.headers['X-Etablissement-Id'] = etablissementId
                  .toString();
            }
            if (etablissementName != null && etablissementName.isNotEmpty) {
              options.headers['X-Etablissement-Name'] = etablissementName;
            }
          } catch (_) {
            // Ignore malformed cached establishment payload.
          }
        }

        // Non-superadmin users are always pinned to their own establishment.
        // Backend also enforces this, this is only a client-side safety layer.
        if (role != 'super_admin' && userEtablissementId != null) {
          options.headers['X-Etablissement-Id'] = userEtablissementId.toString();
          final cleanedName = userEtablissementName?.trim();
          if (cleanedName != null && cleanedName.isNotEmpty) {
            options.headers['X-Etablissement-Name'] = cleanedName;
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        final isAuthEndpoint =
            request.path.endsWith(ApiConstants.login) ||
            request.path.endsWith(ApiConstants.refresh) ||
            request.path.endsWith(ApiConstants.me);
        final alreadyRetried = request.extra['retried'] == true;

        if (error.response?.statusCode == 401 &&
            !isAuthEndpoint &&
            !alreadyRetried) {
          final refresh = await tokenStorage.refreshToken();
          if (refresh != null && refresh.isNotEmpty) {
            try {
              final storedBaseUrl = await tokenStorage.apiBaseUrl();
              final effectiveBaseUrl =
                  (storedBaseUrl != null && storedBaseUrl.isNotEmpty)
                  ? storedBaseUrl
                  : ApiConstants.baseUrl;

              final refreshDio = Dio(
                BaseOptions(
                  baseUrl: effectiveBaseUrl,
                  connectTimeout: const Duration(seconds: 30),
                  receiveTimeout: const Duration(seconds: 45),
                  headers: {'Content-Type': 'application/json'},
                ),
              );

              final refreshResp = await refreshDio.post(
                ApiConstants.refresh,
                data: {'refresh': refresh},
              );

              final newAccess = refreshResp.data['access'] as String;
              final newRefresh =
                  (refreshResp.data['refresh'] as String?) ?? refresh;
              await tokenStorage.saveTokens(
                access: newAccess,
                refresh: newRefresh,
              );

              final retriedOptions = request.copyWith(
                headers: {
                  ...request.headers,
                  'Authorization': 'Bearer $newAccess',
                },
              );
              retriedOptions.extra['retried'] = true;

              final response = await dio.fetch(retriedOptions);
              handler.resolve(response);
              return;
            } catch (_) {
              await tokenStorage.clear();
            }
          }
        }

        final canRetryNetworkError =
            _isTransientNetworkError(error) &&
            _isIdempotentMethod(request.method) &&
            request.extra['retried_network'] != true;

<<<<<<< HEAD
=======
        final hadCustomBaseUrl = request.extra['had_custom_base_url'] == true;
        final usedBaseUrl =
            request.extra['effective_base_url']?.toString() ?? '';
        final fallbackToDefaultAvailable =
            hadCustomBaseUrl &&
            usedBaseUrl.isNotEmpty &&
            !_sameBaseUrl(usedBaseUrl, ApiConstants.baseUrl) &&
            request.extra['retried_with_default_base_url'] != true;

        if (fallbackToDefaultAvailable &&
            _isTransientNetworkError(error) &&
            _isIdempotentMethod(request.method)) {
          final fallbackOptions = request.copyWith(
            baseUrl: ApiConstants.baseUrl,
          );
          fallbackOptions.extra['retried_with_default_base_url'] = true;
          try {
            final response = await dio.fetch(fallbackOptions);
            await tokenStorage.clearApiBaseUrl();
            handler.resolve(response);
            return;
          } catch (_) {
            // Continue with regular retry/error flow below.
          }
        }

>>>>>>> main
        if (canRetryNetworkError) {
          final retriedOptions = request.copyWith();
          retriedOptions.extra['retried_network'] = true;
          try {
            final response = await dio.fetch(retriedOptions);
            handler.resolve(response);
            return;
          } catch (_) {
            // Continue with original error if retry fails.
          }
        }

        handler.next(error);
      },
    ),
  );

  return dio;
});
