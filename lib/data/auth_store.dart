import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/json.dart';

/// Keeps the signed-in user (login response, includes access_token) in the device's secure storage.
class AuthStore {
  static const _key = 'sdms_login';
  static const _storage = FlutterSecureStorage();

  Future<Json?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(Json user) async {
    await _storage.write(key: _key, value: jsonEncode(user));
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}
