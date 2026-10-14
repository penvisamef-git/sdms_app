import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/env.dart';
import '../core/json.dart';

/// An error with the message the server sent (already in Khmer for most cases).
class ApiException implements Exception {
  ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Talks to sdms_api: adds x-api-key + Bearer token, turns failures into [ApiException],
/// keeps a small 60 s cache for lists that rarely change (cleared after any save/delete).
class ApiClient {
  ApiClient({required this.tokenProvider, required this.onUnauthorized})
      : _dio = Dio(
          BaseOptions(
            baseUrl: Env.apiBase,
            connectTimeout: const Duration(seconds: 25),
            // the first call after a pause can be slow (serverless cold start)
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 60),
            headers: {'x-api-key': Env.apiKey},
            validateStatus: (_) => true,
          ),
        );

  final Dio _dio;
  final String? Function() tokenProvider;
  final void Function() onUnauthorized;

  // ---- cache (same idea as the web api.client.js) ----
  static const Duration _cacheFor = Duration(seconds: 120);
  // screens people jump back to (tabs, back from a document): instant for a few seconds.
  // Pull-to-refresh and every save clear the cache, so nothing stays stale after the user's own actions.
  static const Duration _shortFor = Duration(seconds: 20);
  static final List<RegExp> _shortLived = [
    RegExp(r'^/home/(summary|new-documents)'),
    RegExp(r'^/document-transfer/(inbox|sent)'),
    RegExp(r'^/document(\?.*)?$'),
    RegExp(r'^/document/[^/?]+(/tracking)?$'),
  ];
  static final List<RegExp> _cacheable = [
    RegExp(r'^/master-data/'),
    RegExp(r'^/users-all'),
    RegExp(r'^/users-roles'),
    RegExp(r'^/group-user-permission-all'),
    RegExp(r'^/home/my-office'),
  ];
  final Map<String, ({DateTime at, Json json})> _cache = {};
  final Map<String, Future<Json>> _inflight = {};

  Duration? _ttlFor(String path) {
    if (_cacheable.any((re) => re.hasMatch(path))) return _cacheFor;
    if (_shortLived.any((re) => re.hasMatch(path))) return _shortFor;
    return null;
  }

  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  Map<String, dynamic>? _cleanParams(Map<String, dynamic>? params) {
    if (params == null) return null;
    final out = <String, dynamic>{};
    params.forEach((k, v) {
      if (v == null || v == '') return;
      out[k] = v is Map || v is List ? _encodeObject(v) : v;
    });
    return out;
  }

  // the API reads arrays / objects in the query as JSON text
  String _encodeObject(Object v) => jsonEncode(v);

  Future<Json> get(String path, {Map<String, dynamic>? params}) async {
    final ttl = _ttlFor(path);
    if (ttl == null) return _request('GET', path, params: params);

    final clean = _cleanParams(params);
    final key = '$path?${Uri(queryParameters: clean?.map((k, v) => MapEntry(k, '$v'))).query}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.json;

    final running = _inflight[key];
    if (running != null) return running;

    final future = _request('GET', path, params: params).then((json) {
      if (_cache.length > 80) _cache.clear();
      _cache[key] = (at: DateTime.now(), json: json);
      return json;
    }).whenComplete(() => _inflight.remove(key));
    _inflight[key] = future;
    return future;
  }

  Future<Json> post(String path, {Object? body, bool skipAuth = false}) =>
      _mutate('POST', path, body: body, skipAuth: skipAuth);

  Future<Json> put(String path, {Object? body}) => _mutate('PUT', path, body: body);

  Future<Json> delete(String path) => _mutate('DELETE', path);

  Future<Json> _mutate(String method, String path, {Object? body, bool skipAuth = false}) async {
    try {
      return await _request(method, path, body: body, skipAuth: skipAuth);
    } finally {
      clearCache();
    }
  }

  Future<Json> _request(
    String method,
    String path, {
    Map<String, dynamic>? params,
    Object? body,
    bool skipAuth = false,
  }) async {
    final headers = <String, dynamic>{};
    final token = tokenProvider();
    if (!skipAuth && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    Response<dynamic> res;
    try {
      res = await _send(method, path, params, body, headers);
    } on DioException catch (e) {
      // one quiet retry for reads: a cold serverless start often drops the first connection
      if (method == 'GET' && _isNetwork(e)) {
        try {
          res = await _send(method, path, params, body, headers);
        } on DioException {
          throw ApiException('មិនអាចភ្ជាប់ទៅម៉ាសុីនមេបានទេ!');
        }
      } else {
        throw ApiException('មិនអាចភ្ជាប់ទៅម៉ាសុីនមេបានទេ!');
      }
    }

    final data = res.data;
    final json = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final status = res.statusCode ?? 0;

    if (status == 401 && !skipAuth) onUnauthorized();

    if (status < 200 || status >= 300 || json['success'] == false) {
      final msg = s(json['message']);
      throw ApiException(msg.isNotEmpty ? msg : 'Request failed ($status)', status: status);
    }
    return json;
  }

  Future<Response<dynamic>> _send(
    String method,
    String path,
    Map<String, dynamic>? params,
    Object? body,
    Map<String, dynamic> headers,
  ) {
    return _dio.request<dynamic>(
      path,
      data: body,
      queryParameters: _cleanParams(params),
      options: Options(method: method, headers: headers, contentType: body is FormData ? null : Headers.jsonContentType),
    );
  }

  bool _isNetwork(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout;
}
