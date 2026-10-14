import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/json.dart';
import '../core/permission.dart';
import '../features/account/account_page.dart';
import '../features/admin/admin_page.dart';
import '../features/admin/master_list_page.dart';
import '../features/admin/user_list_page.dart';
import '../features/auth/login_page.dart';
import '../features/documents/doc_form_page.dart';
import '../features/documents/doc_list_page.dart';
import '../features/documents/doc_view_page.dart';
import '../features/documents/file_viewer_page.dart';
import '../features/home/home_page.dart';
import '../features/shell/app_shell.dart';
import 'providers.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = ref.read(authProvider);
    final path = state.matchedLocation;

    if (!auth.ready) return path == '/splash' ? null : '/splash';
    if (!auth.loggedIn) return path == '/login' ? null : '/login';
    if (path == '/login' || path == '/splash' || path == '/') return '/home';

    // role rules (same as the web menu)
    final user = auth.user;
    if (path.startsWith('/document/in') && !canAccess(user, Access.docIn)) return '/home';
    if (path.startsWith('/document/out') && !canAccess(user, Access.docOut)) return '/home';
    if (path.startsWith('/admin') && !canAccess(user, Access.superAdmin)) return '/home';
    return null;
  }

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/document/in', builder: (_, __) => const DocListPage(box: 'in')),
          GoRoute(path: '/document/out', builder: (_, __) => const DocListPage(box: 'out')),
          GoRoute(path: '/admin', builder: (_, __) => const AdminPage()),
          GoRoute(path: '/account', builder: (_, __) => const AccountPage()),
        ],
      ),
      // full-screen pages (no bottom bar)
      GoRoute(
        path: '/document/out/create',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const DocFormPage(),
      ),
      GoRoute(
        path: '/document/out/edit/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => DocFormPage(documentId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/document/:box/view/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => DocViewPage(
          id: state.pathParameters['id']!,
          box: state.pathParameters['box'] == 'out' ? 'out' : 'in',
        ),
      ),
      GoRoute(
        path: '/file',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => FileViewerPage(
          args: state.extra is FileViewArgs ? state.extra as FileViewArgs : FileViewArgs(asObj(state.extra)),
        ),
      ),
      GoRoute(
        path: '/admin/users',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const UserListPage(),
      ),
      GoRoute(
        path: '/admin/master/:key',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => MasterListPage(masterKey: state.pathParameters['key']!),
      ),
    ],
  );
});
