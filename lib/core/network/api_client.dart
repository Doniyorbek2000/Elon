import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../config/app_config.dart';
import '../domain/paged.dart';
import '../errors/app_failure.dart';
import '../logging/app_logger.dart';
import '../storage/secure_store.dart';

typedef JsonMap = Map<String, dynamic>;

/// Typed wrapper around Dio for the `/api/v1` contract:
///
/// * success: `{ "data": …, "meta"?: { "nextCursor": … } }`
/// * failure: `{ "error": { "code", "message", "details"?, "requestId" } }`
///
/// All remote repositories go through here so auth, token refresh, logging
/// and error mapping live in exactly one place. Tokens are never logged.
class ApiClient {
  ApiClient({required this._dio, required this._logger});

  final Dio _dio;
  final AppLogger _logger;

  /// GET returning the unwrapped `data` payload.
  Future<T> get<T>(String path, {Map<String, Object?>? query}) async =>
      _data<T>(await _send(() => _dio.get<Object?>(path, queryParameters: _clean(query))));

  /// GET for cursor-paginated collections.
  Future<PageResult<T>> getPage<T>(
    String path,
    T Function(JsonMap json) parse, {
    Map<String, Object?>? query,
    String? cursor,
  }) async {
    final body = await _send(() => _dio.get<Object?>(path, queryParameters: _clean({...?query, 'cursor': cursor})));
    final items = _data<List<dynamic>>(body);
    final meta = body['meta'] is Map ? body['meta'] as JsonMap : const <String, dynamic>{};
    return PageResult(
      items: [for (final item in items) parse(item as JsonMap)],
      nextCursor: meta['nextCursor'] as String?,
    );
  }

  Future<T> post<T>(String path, {Object? body}) async =>
      _data<T>(await _send(() => _dio.post<Object?>(path, data: body)));

  Future<T> put<T>(String path, {Object? body}) async =>
      _data<T>(await _send(() => _dio.put<Object?>(path, data: body)));

  Future<T> patch<T>(String path, {Object? body}) async =>
      _data<T>(await _send(() => _dio.patch<Object?>(path, data: body)));

  Future<void> delete(String path, {Object? body}) async {
    await _send(() => _dio.delete<Object?>(path, data: body));
  }

  Future<JsonMap> upload(
    String path, {
    required FormData data,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async => _data<JsonMap>(
    await _send(
      () => _dio.post<Object?>(
        path,
        data: data,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(sendTimeout: const Duration(minutes: 2)),
      ),
    ),
  );

  Map<String, Object?>? _clean(Map<String, Object?>? query) =>
      query == null ? null : (Map.of(query)..removeWhere((_, value) => value == null || value == ''));

  T _data<T>(JsonMap body) {
    final data = body['data'];
    if (data is T) return data;
    throw ServerFailure(tr('Kutilmagan server javobi'), statusCode: 200);
  }

  Future<JsonMap> _send(Future<Response<Object?>> Function() request) async {
    try {
      final response = await request();
      final data = response.data;
      return data is JsonMap ? data : <String, dynamic>{'data': data};
    } on DioException catch (error, stackTrace) {
      final failure = error.error is AppFailure ? error.error! as AppFailure : mapDioException(error);
      _logger.warning('API ${error.requestOptions.method} ${error.requestOptions.path} → ${failure.runtimeType}');
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
        return mapErrorResponse(error.response?.statusCode, error.response?.data, error.response?.headers);
      case DioExceptionType.cancel:
        return UnknownFailure(tr('So‘rov bekor qilindi'));
      case DioExceptionType.badCertificate:
        return ServerFailure(tr('Xavfsiz ulanib bo‘lmadi'));
      case DioExceptionType.unknown:
        return error.error is SocketException ? const NetworkFailure() : const UnknownFailure();
    }
  }

  /// Maps the server error envelope to a typed failure.
  static AppFailure mapErrorResponse(int? status, Object? body, [Headers? headers]) {
    final error = body is Map && body['error'] is Map
        ? body['error'] as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final code = error['code'] as String?;
    final serverMessage = error['message'] as String?;
    final details = error['details'] is Map ? error['details'] as Map<Object?, Object?> : const <Object?, Object?>{};
    final message = _localizedMessage(code) ?? serverMessage ?? tr('Server xatosi');
    switch (code) {
      case 'LIMIT_REACHED':
        final max = (details['max'] as num?)?.toInt();
        final limit = details['limit'] as String? ?? '';
        return LimitReachedFailure(_limitMessage(limit, max), limit: limit, max: max);
      case 'FEATURE_DISABLED':
        return const FeatureDisabledFailure();
      case 'PAYMENT_ROUTE_UNAVAILABLE':
      case 'PROVIDER_NOT_CONFIGURED':
        return const PaymentUnavailableFailure();
    }
    switch (status) {
      case 401:
        return UnauthorizedFailure(_localizedMessage(code) ?? tr('Tizimga qayta kiring'));
      case 403:
        return code == 'BLOCKED' ? const BlockedFailure() : ForbiddenFailure(message);
      case 404:
        return const NotFoundFailure();
      case 409:
        return ConflictFailure(message, code: code);
      case 413:
        return ValidationFailure(tr('Fayl hajmi juda katta'), code: 'PAYLOAD_TOO_LARGE');
      case 415:
        return ValidationFailure(
          tr('Bu fayl turi qo‘llab-quvvatlanmaydi (JPEG, PNG, WebP, HEIC)'),
          code: 'UNSUPPORTED_MEDIA',
        );
      case 400:
      case 422:
        return ValidationFailure(message, fieldErrors: _fieldErrors(details), code: code);
      case 429:
        final seconds =
            (details['retryAfterSeconds'] as num?)?.toInt() ?? int.tryParse(headers?.value('retry-after') ?? '');
        return RateLimitFailure(
          _localizedMessage(code) ?? tr('Juda ko‘p so‘rov. Birozdan so‘ng urinib ko‘ring'),
          seconds == null ? null : Duration(seconds: seconds),
        );
      default:
        return ServerFailure(
          status != null && status >= 500 ? tr('Serverda nosozlik. Keyinroq urinib ko‘ring') : message,
          statusCode: status,
        );
    }
  }

  static Map<String, String> _fieldErrors(Map<Object?, Object?> details) {
    final fields = details['fields'];
    if (fields is Map) return fields.map((key, value) => MapEntry('$key', '$value'));
    if (details['field'] is String) return {details['field'] as String: tr('Noto‘g‘ri qiymat')};
    return const {};
  }

  static String _limitMessage(String limit, int? max) {
    final count = max == null ? '' : tr(' ({max} ta)', {'max': max});
    return switch (limit) {
      'activeListings' => tr(
        'Faol e’lonlar chegarasiga yetdingiz{count}. Eskisini arxivlang yoki tarifni kengaytiring',
        {'count': count},
      ),
      'monthlyListings' => tr('Shu oy uchun e’lonlar chegarasiga yetdingiz{count}', {'count': count}),
      'photos' => tr('Rasmlar soni chegaradan oshdi{count}', {'count': count}),
      'activeJobs' => tr('Faol vakansiyalar chegarasiga yetdingiz{count}', {'count': count}),
      'managers' => tr('Menejerlar soni chegarasiga yetdingiz{count}', {'count': count}),
      _ => tr('Tarif chegarasiga yetdingiz{count}', {'count': count}),
    };
  }

  static String? _localizedMessage(String? code) => switch (code) {
    'OTP_INVALID' => tr('Kod noto‘g‘ri. Qayta urinib ko‘ring'),
    'OTP_EXPIRED' => tr('Kod muddati tugadi. Yangi kod so‘rang'),
    'OTP_TOO_MANY_ATTEMPTS' => tr('Urinishlar ko‘p bo‘ldi. Yangi kod so‘rang'),
    'OTP_COOLDOWN' => tr('Yangi kodni biroz kutib so‘rang'),
    'SESSION_REVOKED' => tr('Sessiya tugatildi. Qayta kiring'),
    'TOKEN_EXPIRED' => tr('Sessiya muddati tugadi'),
    'NOT_ELIGIBLE' => tr('Sharh qoldirish uchun avval usta bilan yozishgan bo‘lishingiz kerak'),
    'BLOCKED' => tr('Bu foydalanuvchi bilan yozishib bo‘lmaydi'),
    'COUPON_INVALID' => tr('Promo kod yaroqsiz'),
    'INSUFFICIENT_CREDITS' => tr('Kreditlar yetarli emas'),
    'PRICE_UNAVAILABLE' => tr('Bu xizmat hozircha sotuvda emas'),
    _ => null,
  };
}

/// Access/refresh tokens in secure storage plus a signal for forced sign-out.
class TokenStore {
  TokenStore(this._secure);

  final SecureStore _secure;
  final _expired = StreamController<void>.broadcast();

  /// Emits when the refresh token was rejected (revoked/reused/expired).
  Stream<void> get sessionExpired => _expired.stream;

  Future<String?> get accessToken => _secure.read(SecureStoreKey.accessToken);
  Future<String?> get refreshToken => _secure.read(SecureStoreKey.refreshToken);

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _secure.write(SecureStoreKey.accessToken, accessToken);
    await _secure.write(SecureStoreKey.refreshToken, refreshToken);
  }

  Future<void> clear() async {
    await _secure.delete(SecureStoreKey.accessToken);
    await _secure.delete(SecureStoreKey.refreshToken);
  }

  Future<void> expire() async {
    await clear();
    _expired.add(null);
  }

  void dispose() => _expired.close();
}

/// Attaches the bearer token and transparently refreshes it once on 401.
/// [QueuedInterceptor] serializes error handling, so concurrent 401s trigger
/// a single rotation; later requests reuse the already-rotated token.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this.tokens, required this.dio, required this.refreshDio});

  final TokenStore tokens;
  final Dio dio;

  /// Separate client without this interceptor (avoids recursion).
  final Dio refreshDio;

  static const _retried = 'auth.retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokens.accessToken;
    if (token != null) options.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    options.headers[HttpHeaders.acceptLanguageHeader] = currentLanguage.code;
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final unauthorized = err.response?.statusCode == 401;
    if (!unauthorized || request.extra[_retried] == true || request.path.contains('/auth/')) {
      return handler.next(err);
    }
    final sentToken = (request.headers[HttpHeaders.authorizationHeader] as String?)?.replaceFirst('Bearer ', '');
    final current = await tokens.accessToken;
    if (current == null) return handler.next(err);

    try {
      // Another request already rotated the token while this one was in flight.
      final token = current != sentToken ? current : await _refresh();
      if (token == null) return handler.next(err);
      final retry = request.copyWith(
        headers: {...request.headers, HttpHeaders.authorizationHeader: 'Bearer $token'},
        extra: {...request.extra, _retried: true},
      );
      handler.resolve(await dio.fetch<Object?>(retry));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Returns the new access token, or null when the session is over.
  Future<String?> _refresh() async {
    final refreshToken = await tokens.refreshToken;
    if (refreshToken == null) {
      await tokens.expire();
      return null;
    }
    try {
      final response = await refreshDio.post<JsonMap>('/auth/refresh', data: {'refreshToken': refreshToken});
      final data = response.data?['data'] as JsonMap?;
      final access = data?['accessToken'] as String?;
      final refresh = data?['refreshToken'] as String?;
      if (access == null || refresh == null) throw ServerFailure(tr('Kutilmagan server javobi'));
      await tokens.save(accessToken: access, refreshToken: refresh);
      return access;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        await tokens.expire();
        return null;
      }
      // Offline/timeout: keep the session; surface the transport failure.
      rethrow;
    }
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  final store = TokenStore(ref.watch(secureStoreProvider));
  ref.onDispose(store.dispose);
  return store;
});

BaseOptions _baseOptions(AppConfig config) => BaseOptions(
  baseUrl: config.apiBaseUrl,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 20),
  sendTimeout: const Duration(seconds: 30),
  contentType: Headers.jsonContentType,
  responseType: ResponseType.json,
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio(_baseOptions(config));
  final refreshDio = Dio(_baseOptions(config));
  dio.interceptors.add(AuthInterceptor(tokens: ref.watch(tokenStoreProvider), dio: dio, refreshDio: refreshDio));
  ref.onDispose(() {
    dio.close();
    refreshDio.close();
  });
  return ApiClient(dio: dio, logger: ref.watch(appLoggerProvider));
});
