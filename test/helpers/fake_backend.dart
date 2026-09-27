import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bozor/core/logging/app_logger.dart';
import 'package:bozor/core/network/api_client.dart';
import 'package:bozor/core/storage/secure_store.dart';
import 'package:dio/dio.dart';

/// Scripted HTTP backend: each handler returns (status, json body).
class FakeBackend implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final Map<String, FutureOr<(int, Object?)> Function(RequestOptions)> routes = {};

  void on(String method, String path, FutureOr<(int, Object?)> Function(RequestOptions) handler) =>
      routes['$method $path'] = handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = routes['${options.method} ${options.path}'];
    if (handler == null) {
      return ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'NOT_FOUND'},
        }),
        404,
        headers: _json,
      );
    }
    final (status, body) = await handler(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: _json);
  }

  static const _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}

class SilentLogger implements AppLogger {
  @override
  void log(LogLevel level, String message, {Object? error, StackTrace? stackTrace, String tag = 'app'}) {}
}

({ApiClient api, FakeBackend backend, TokenStore tokens}) buildClient() {
  final backend = FakeBackend();
  final tokens = TokenStore(MemorySecureStore());
  final options = BaseOptions(baseUrl: 'https://api.test/api/v1', contentType: Headers.jsonContentType);
  final dio = Dio(options)..httpClientAdapter = backend;
  final refreshDio = Dio(options)..httpClientAdapter = backend;
  dio.interceptors.add(AuthInterceptor(tokens: tokens, dio: dio, refreshDio: refreshDio));
  return (api: ApiClient(dio: dio, logger: SilentLogger()), backend: backend, tokens: tokens);
}

Map<String, Object?> error(String code, [Map<String, Object?>? details]) => {
  'error': {'code': code, 'message': 'server message', 'details': ?details, 'requestId': 'req-1'},
};
