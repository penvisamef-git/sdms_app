import 'dart:convert';
import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/json.dart';
import '../../data/auth_store.dart';
import 'signature_pad.dart';

/// The signature a user drew once, kept on the phone (encrypted storage) so the next document
/// takes one tap instead of drawing it again. One signature per account.
class SignatureStore {
  static const _storage = FlutterSecureStorage();

  static Future<String> _key() async {
    final user = await AuthStore().read();
    final id = s(user?['_id']);
    return 'sdms_signature_${id.isEmpty ? 'me' : id}';
  }

  static Future<SignatureResult?> load() async {
    try {
      final raw = await _storage.read(key: await _key());
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final strokes = <List<Offset>>[];
      for (final st in (m['s'] as List)) {
        final flat = (st as List).map((e) => (e as num).toDouble()).toList();
        strokes.add([for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i], flat[i + 1])]);
      }
      if (strokes.isEmpty) return null;
      return SignatureResult(
        strokes: strokes,
        width: (m['w'] as num).toDouble(),
        color: Color((m['c'] as num).toInt()),
        ratio: (m['r'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  static Future<void> save(SignatureResult r) async {
    try {
      final data = {
        'w': _r(r.width),
        'c': r.color.toARGB32(),
        'r': _r(r.ratio),
        's': [
          for (final st in r.strokes)
            [for (final p in st) ...[_r(p.dx), _r(p.dy)]],
        ],
      };
      await _storage.write(key: await _key(), value: jsonEncode(data));
    } catch (_) {
      // not being able to remember is fine: the signature was still placed
    }
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: await _key());
    } catch (_) {}
  }
}
