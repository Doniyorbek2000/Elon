import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../errors/app_failure.dart';
import '../logging/app_logger.dart';
import '../storage/secure_store.dart';

typedef JsonMap = Map<String, dynamic>;

/// Thin typed wrapper around Dio. All remote repositories go through here so
/// auth, logging and error mapping live in exactly one place.
class ApiClient {
  ApiClient({required this._dio, required this._logger});

  final Dio _dio;
  final AppLogger _logger;

  Future<JsonMap> getJson(String path, {Map<String, Object?>? query}) =>
      _guard(() => _dio.get<JsonMap>(path, queryParameters: _clean(query)));

  Future<JsonMap> postJson(String path, {Object? body}) => _guard(() => _dio.post<JsonMap>(path, data: body));

  Future<JsonMap> patchJson(String path, {Object? body}) => _guard(() => _dio.patch<JsonMap>(path, data: body));

  Future<void> delete(String path) async {
    await _guard(() => _dio.delete<JsonMap>(path));
  }

  Future<JsonMap> upload(
    String path, {
    required FormData data,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) => _guard(() => _dio.post<JsonMap>(path, data: data, onSendProgress: onProgress, cancelToken: cancelToken));

  Map<String, Object?>? _clean(Map<String, Object?>? query) =>
      query == null ? null : (Map.of(query)..removeWhere((_, value) => value == null || value == ''));

  Future<JsonMap> _guard(Future<Response<JsonMap>> Function() request) async {
    try {
      final response = await request();
      return response.data ?? const {};
    } on DioException catch (error, stackTrace) {
      final failure = mapDioException(error);
      _logger.warning('API ${error.requestOptions.method} ${error.requestOptions.path} → $failure', error: error);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  static AppFailure mapDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        final data = error.response?.data;
        final message = data is Map && data['message'] is String ? data['message'] as String : 'Server xatosi';
        return switch (status) {
          401 || 403 => const UnauthorizedFailure(),
          404 => const NotFoundFailure(),
          422 || 400 => ValidationFailure(
            message,
            fieldErrors: data is Map && data['errors'] is Map
                ? (data['errors'] as Map).map((key, value) => MapEntry('$key', '$value'))
                : const {},
          ),
          429 => const RateLimitFailure(),
          _ => ServerFailure(message, statusCode: status),
        };
      case DioExceptionType.cancel:
        return const UnknownFailure('So‘rov bekor qilindi');
      case DioExceptionType.badCertificate:
        return const ServerFailure('Xavfsiz ulanib bo‘lmadi');
      case DioExceptionType.unknown:
        return error.error is SocketException ? const NetworkFailure() : const UnknownFailure();
    }
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._secureStore);

  final SecureStore _secureStore;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _secureStore.read(SecureStoreKey.accessToken);
    if (token != null) options.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    options.headers[HttpHeaders.acceptLanguageHeader] = 'uz';
    handler.next(options);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 60),
    ),
  )..interceptors.add(_AuthInterceptor(ref.watch(secureStoreProvider)));
  ref.onDispose(dio.close);
  return ApiClient(dio: dio, logger: ref.watch(appLoggerProvider));
});
