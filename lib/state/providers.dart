import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/json.dart';
import '../data/api_client.dart';
import '../data/auth_store.dart';
import '../data/services.dart';

class AuthState {
  const AuthState({this.ready = false, this.user});

  /// false while the saved login is being read from the device
  final bool ready;
  final Json? user;

  String get token => s(user?['access_token']);
  bool get loggedIn => user != null && token.isNotEmpty;
}

final authStoreProvider = Provider<AuthStore>((ref) => AuthStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenProvider: () => ref.read(authProvider).token,
    onUnauthorized: () => ref.read(authProvider.notifier).sessionExpired(),
  );
});

final apiProvider = Provider<Api>((ref) => Api(ref.watch(apiClientProvider)));

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _load();
    return const AuthState();
  }

  Future<void> _load() async {
    final saved = await ref.read(authStoreProvider).read();
    state = AuthState(ready: true, user: saved);
    if (saved != null) refreshProfile();
  }

  Future<void> login(String email, String password) async {
    final res = await ref.read(apiProvider).login(email.trim(), password);
    final data = asObj(res['data']);
    if (s(data['access_token']).isEmpty) throw ApiException('ចូលគណនីមិនបានសម្រេច');
    // never keep a password hash on the phone
    data.remove('password');
    if (data['user_data'] is Map) (data['user_data'] as Map).remove('password');
    await ref.read(authStoreProvider).save(data);
    ref.read(apiClientProvider).clearCache();
    state = AuthState(ready: true, user: data);
  }

  /// Keep the saved login in step with the server (e.g. an admin changed my role).
  Future<void> refreshProfile() async {
    try {
      final res = await ref.read(apiProvider).profile();
      final d = asObj(res['data']);
      final fresh = d['user'] is Map ? asObj(d['user']) : d;
      final current = state.user;
      if (current == null || fresh.isEmpty) return;
      final next = Map<String, dynamic>.from(current);
      var changed = false;
      for (final k in const ['role', 'is_super_admin', 'firstname', 'lastname', 'contact', 'job_title']) {
        if (fresh.containsKey(k) && fresh[k] != current[k]) {
          next[k] = fresh[k];
          changed = true;
        }
      }
      if (changed) {
        await ref.read(authStoreProvider).save(next);
        state = AuthState(ready: true, user: next);
      }
    } catch (_) {
      // offline or token problems are handled by the API client
    }
  }

  Future<void> logout() async {
    await ref.read(apiProvider).logout();
    await _clear();
  }

  /// The server said 401: the session is gone.
  void sessionExpired() {
    if (state.user != null) _clear();
  }

  Future<void> _clear() async {
    await ref.read(authStoreProvider).clear();
    ref.read(apiClientProvider).clearCache();
    state = const AuthState(ready: true);
  }
}
