import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/push_service.dart';
import 'state/providers.dart';
import 'state/router.dart';
import 'state/theme_mode.dart';

class SdmsApp extends ConsumerStatefulWidget {
  const SdmsApp({super.key});

  @override
  ConsumerState<SdmsApp> createState() => _SdmsAppState();
}

class _SdmsAppState extends ConsumerState<SdmsApp> with WidgetsBindingObserver {
  DateTime _warmAt = DateTime.fromMillisecondsSinceEpoch(0);

  // personal deep link:  sdms://auto-login?t=<token>
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  String _lastLinkToken = '';

  @override
  void initState() {
    super.initState();
    PushService.instance.pending.addListener(_openPending);
    WidgetsBinding.instance.addObserver(this);
    _warm();
    _listenLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.pending.removeListener(_openPending);
    super.dispose();
  }

  /// The app opened with a link (cold start) or received one while running.
  Future<void> _listenLinks() async {
    try {
      final first = await _appLinks.getInitialLink();
      if (first != null) _onLink(first);
    } catch (_) {}
    _linkSub = _appLinks.uriLinkStream.listen(_onLink, onError: (_) {});
  }

  Future<void> _onLink(Uri uri) async {
    if (uri.scheme != 'sdms' || uri.host != 'auto-login') return;
    final token = uri.queryParameters['t'] ?? '';
    // the same link can be delivered twice (initial link + stream): use it once
    if (token.isEmpty || token == _lastLinkToken) return;
    _lastLinkToken = token;
    final messenger = scaffoldMessengerKey.currentState;
    try {
      await ref.read(authProvider.notifier).loginWithLink(token);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// Wake the (serverless) API while the user is still looking at the splash / login screen.
  void _warm() {
    _warmAt = DateTime.now();
    ref.read(apiProvider).warmUp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back to the app after a pause: the server may have gone to sleep
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_warmAt) > const Duration(minutes: 3)) {
      _warm();
    }
  }

  /// A notification was tapped: open its document as soon as the user is signed in.
  void _openPending() {
    final target = PushService.instance.pending.value;
    if (target == null || !ref.read(authProvider).loggedIn) return;
    PushService.instance.pending.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routerProvider).push('/document/${target.box}/view/${target.id}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    // cold start from a notification: wait for the saved login to load
    ref.listen<AuthState>(authProvider, (_, next) {
      if (next.loggedIn) _openPending();
    });
    return MaterialApp.router(
      title: 'SDMS',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) {
        // keep the layout stable when the phone uses a very large font size
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
