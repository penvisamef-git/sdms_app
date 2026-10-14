import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/permission.dart';
import '../../state/providers.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.path);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
}

/// Bottom navigation. A tab shows only when the user's role may open it.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    final tabs = <_Tab>[
      const _Tab('ទំព័រដើម', Icons.dashboard_outlined, Icons.dashboard_rounded, '/home'),
      if (canAccess(user, Access.docIn))
        const _Tab('ឯកសារចូល', Icons.move_to_inbox_outlined, Icons.move_to_inbox_rounded, '/document/in'),
      if (canAccess(user, Access.docOut))
        const _Tab('ឯកសារចេញ', Icons.outbox_outlined, Icons.outbox_rounded, '/document/out'),
      if (canAccess(user, Access.superAdmin))
        const _Tab('គ្រប់គ្រង', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded, '/admin'),
      const _Tab('គណនី', Icons.person_outline_rounded, Icons.person_rounded, '/account'),
    ];

    var index = tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
