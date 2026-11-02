import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Fixed header of a bottom-navigation page: it stays on top while the page below scrolls.
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.bottom});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// extra controls under the title (month picker, search ...)
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: AppColors.card(context),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall?.copyWith(color: AppColors.muted)),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 8),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}
