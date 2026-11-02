import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Appearance chosen by the user: follow the phone (system), always light, or always dark.
/// Kept on the device; it stays when the user signs out.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'sdms_theme_mode';
  static const _storage = FlutterSecureStorage();

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final saved = await _storage.read(key: _key);
      for (final m in ThemeMode.values) {
        if (m.name == saved) {
          state = m;
          return;
        }
      }
    } catch (_) {
      // unreadable storage: keep following the system
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {}
  }
}
