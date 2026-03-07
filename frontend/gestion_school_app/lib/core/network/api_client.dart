import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final dioProvider = Provider<Dio>((ref) {
  final tokenStorage = ref.read(tokenStorageProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final storedBaseUrl = await tokenStorage.apiBaseUrl();
        final effectiveBaseUrl =
            (storedBaseUrl != null && storedBaseUrl.isNotEmpty)
            ? storedBaseUrl
            : ApiConstants.baseUrl;
        options.baseUrl = effectiveBaseUrl;

        final token = await tokenStorage.accessToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
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
                  connectTimeout: const Duration(seconds: 10),
                  receiveTimeout: const Duration(seconds: 15),
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

        handler.next(error);
      },
    ),
  );

  return dio;
});
