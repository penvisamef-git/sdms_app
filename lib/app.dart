import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/push_service.dart';
import 'state/providers.dart';
import 'state/router.dart';

class SdmsApp extends ConsumerStatefulWidget {
  const SdmsApp({super.key});

  @override
  ConsumerState<SdmsApp> createState() => _SdmsAppState();
}

class _SdmsAppState extends ConsumerState<SdmsApp> {
  @override
  void initState() {
    super.initState();
    PushService.instance.pending.addListener(_openPending);
  }

  @override
  void dispose() {
    PushService.instance.pending.removeListener(_openPending);
    super.dispose();
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
      themeMode: ThemeMode.system,
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
