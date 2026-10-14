import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../core/env.dart';
import '../core/json.dart';
import 'services.dart';

/// Lets a notification that arrives while the app is open show a message bar.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// A document the user asked to open from a notification.
class PushTarget {
  const PushTarget(this.box, this.id);

  /// 'in' (incoming) or 'out' (outgoing)
  final String box;
  final String id;
}

/// Push notifications (Firebase Cloud Messaging).
///
/// Everything here is best-effort: when Firebase is not set up (no google-services.json /
/// GoogleService-Info.plist) the service stays off and the app works exactly as before.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// Set when the user taps a notification (or the "view" action). The app opens it once signed in.
  final ValueNotifier<PushTarget?> pending = ValueNotifier<PushTarget?>(null);

  Future<void>? _init;
  bool _ready = false;
  String? _token;
  Api? _api;
  StreamSubscription<String>? _refreshSub;

  bool get ready => _ready;

  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    // iOS needs GoogleService-Info.plist + the Push capability first: switch on with --dart-define=PUSH_IOS=true
    if (Platform.isIOS && !Env.pushIos) return;
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      _ready = true;
    } catch (_) {
      _ready = false;
      return;
    }
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      FirebaseMessaging.onMessage.listen(_onForeground);
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _onOpened(first);
    } catch (_) {}
  }

  PushTarget? _targetOf(RemoteMessage m) {
    final id = s(m.data['document_id']);
    if (id.isEmpty) return null;
    return PushTarget(s(m.data['kind']) == 'done' ? 'out' : 'in', id);
  }

  void _onOpened(RemoteMessage m) {
    final t = _targetOf(m);
    if (t != null) pending.value = t;
  }

  void _onForeground(RemoteMessage m) {
    final n = m.notification;
    final text = [s(n?.title), s(n?.body)].where((e) => e.isNotEmpty).join('\n');
    if (text.isEmpty) return;
    final target = _targetOf(m);
    final messenger = scaffoldMessengerKey.currentState;
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: target == null
              ? null
              : SnackBarAction(label: 'មើល', onPressed: () => pending.value = target),
        ),
      );
  }

  /// After sign-in: ask permission, get the phone's token and give it to the server.
  Future<void> register(Api api) async {
    await init();
    if (!_ready) return;
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await fm.getToken();
      if (token == null || token.isEmpty) return;
      _api = api;
      _token = token;
      await _send(api, token);
      _refreshSub ??= fm.onTokenRefresh.listen((t) {
        _token = t;
        final a = _api;
        if (a != null) _send(a, t);
      });
    } catch (_) {
      // no permission, no Google services, offline…: notifications simply stay off
    }
  }

  Future<void> _send(Api api, String token) async {
    try {
      await api.pushRegister(token, Platform.isIOS ? 'ios' : 'android');
    } catch (_) {}
  }

  /// Before sign-out (the session is still valid): the server stops sending to this phone.
  Future<void> unregister(Api api) async {
    if (!_ready) return;
    try {
      final token = _token ?? await FirebaseMessaging.instance.getToken();
      if (token != null) await api.pushUnregister(token);
    } catch (_) {}
    await dropToken();
  }

  /// Forget this phone's token (also used when the session expired and the server cannot be told).
  Future<void> dropToken() async {
    _api = null;
    _token = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
