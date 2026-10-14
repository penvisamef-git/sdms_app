import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class _Entry {
  _Entry(this.at, this.json, {this.stale = false});

  DateTime at;
  Json json;

  /// true after a save / delete / pull-to-refresh: still good to SHOW while the new answer is on its way,
  /// but never served as the final answer.
  bool stale;
}

/// Talks to sdms_api: adds x-api-key + Bearer token, turns failures into [ApiException].
///
/// Cache (stale-while-revalidate):
///  * fresh answers are reused for a few seconds / minutes (see [_ttlFor]);
///  * every answer is also kept on the device, so the next app start can show the last screen at once
///    ([restore] + [peek]) while the new data loads quietly;
///  * a save / delete / pull-to-refresh only marks entries stale (they stay visible, never wrong for long);
///  * [wipe] (sign-in / sign-out) removes everything, in memory and on disk.
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
  final Map<String, _Entry> _cache = {};
  final Map<String, Future<Json>> _inflight = {};

  // After a change the server's own short cache must be skipped too (it may still hold the old list).
  DateTime _serverFreshUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _serverFreshFor = Duration(seconds: 20);

  static const int _maxEntries = 80;
  static const Duration _diskMaxAge = Duration(days: 7);

  Duration? _ttlFor(String path) {
    if (_cacheable.any((re) => re.hasMatch(path))) return _cacheFor;
    if (_shortLived.any((re) => re.hasMatch(path))) return _shortFor;
    return null;
  }

  /// "Something changed": keep what we have for display, but fetch again next time.
  void clearCache() {
    for (final e in _cache.values) {
      e.stale = true;
    }
    _inflight.clear();
    _serverFreshUntil = DateTime.now().add(_serverFreshFor);
  }

  /// Sign-in / sign-out: forget everything, also on the device.
  Future<void> wipe() async {
    _cache.clear();
    _inflight.clear();
    _serverFreshUntil = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final dir = _dir;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  // ---- device copy (a few small json files in the app's cache folder) ----
  Directory get _dir => Directory('${Directory.systemTemp.path}/sdms_cache');

  // FNV-1a: a short, stable file name for a long url
  String _fileName(String key) {
    var h = 0xcbf29ce484222325;
    for (final c in utf8.encode(key)) {
      h ^= c;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${h.toRadixString(16)}.json';
  }

  /// Reads the saved answers back into memory (call once after the saved login is known).
  Future<void> restore() async {
    try {
      final dir = _dir;
      if (!await dir.exists()) return;
      final files = <File>[];
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.json')) files.add(f);
      }
      final now = DateTime.now();
      final loaded = <_Entry>[];
      for (final f in files) {
        try {
          final m = jsonDecode(await f.readAsString());
          final at = DateTime.fromMillisecondsSinceEpoch(m['at'] as int);
          if (now.difference(at) > _diskMaxAge || loaded.length >= _maxEntries) {
            unawaited(f.delete().catchError((_) => f));
            continue;
          }
          // restored answers are never "fresh": they are shown at once and replaced by the real answer
          _cache[m['key'] as String] = _Entry(at, Map<String, dynamic>.from(m['json'] as Map), stale: true);
          loaded.add(_cache[m['key'] as String]!);
        } catch (_) {
          unawaited(f.delete().catchError((_) => f));
        }
      }
    } catch (_) {}
  }

  void _persist(String key, _Entry e) {
    unawaited(() async {
      try {
        final dir = _dir;
        if (!await dir.exists()) await dir.create(recursive: true);
        await File('${dir.path}/${_fileName(key)}')
            .writeAsString(jsonEncode({'key': key, 'at': e.at.millisecondsSinceEpoch, 'json': e.json}));
      } catch (_) {}
    }());
  }

  String _keyFor(String path, Map<String, dynamic>? params) {
    final clean = _cleanParams(params);
    return '$path?${Uri(queryParameters: clean?.map((k, v) => MapEntry(k, '$v'))).query}';
  }

  /// The last answer we have for this call, however old (null if none). Use it to paint a screen at once.
  Json? peek(String path, {Map<String, dynamic>? params}) {
    if (_ttlFor(path) == null) return null;
    return _cache[_keyFor(path, params)]?.json;
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

    final key = _keyFor(path, params);
    final hit = _cache[key];
    if (hit != null && !hit.stale && DateTime.now().difference(hit.at) < ttl) return hit.json;

    final running = _inflight[key];
    if (running != null) return running;

    final future = _request('GET', path, params: params, bypassServerCache: DateTime.now().isBefore(_serverFreshUntil))
        .then((json) {
      if (_cache.length > _maxEntries) _cache.clear();
      final e = _Entry(DateTime.now(), json);
      _cache[key] = e;
      _persist(key, e);
      return json;
    }).catchError((Object err) {
      // offline: an older answer is better than an error screen
      if (err is ApiException && err.status == null && hit != null) return hit.json;
      throw err;
    }).whenComplete(() {
      // a block body on purpose: Map.remove would hand back this very future and whenComplete would wait for itself
      _inflight.remove(key);
    });
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
    bool bypassServerCache = false,
  }) async {
    final headers = <String, dynamic>{};
    if (bypassServerCache) headers['Cache-Control'] = 'no-cache';
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
