import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

const _linkStatus = <String, (String, Tone)>{
  'active': ('កំពុងប្រើបាន', Tone.done),
  'used': ('បានប្រើរួច', Tone.info),
  'expired': ('ផុតកំណត់', Tone.warn),
  'revoked': ('បានលុប', Tone.danger),
};

/// Big Boss: my personal deep links. A link is shown in full only once, right after it is made.
class MyLinksCard extends ConsumerStatefulWidget {
  const MyLinksCard({super.key});

  @override
  ConsumerState<MyLinksCard> createState() => _MyLinksCardState();
}

class _MyLinksCardState extends ConsumerState<MyLinksCard> {
  List<Json> _rows = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ref.read(apiProvider).myLinks();
      if (!mounted) return;
      setState(() => _rows = asList(res['data']));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(Json row) async {
    final ok = await confirmDialog(
      context,
      title: 'លុប Link នេះ?',
      message: 'ឧបករណ៍ដែលចូលដោយ Link នេះនឹងត្រូវចាកចេញ។',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).revokeLink(s(row['_id']));
      if (mounted) _load();
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _create() async {
    final label = TextEditingController();
    final password = TextEditingController();
    int days = 30;
    bool once = false;
    bool saving = false;
    String error = '';
    String webUrl = '';
    String appUrl = '';

    Future<void> copy(BuildContext ctx, String text) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (ctx.mounted) showSnack(ctx, 'បានចម្លង');
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('បង្កើត Link ថ្មី'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (webUrl.isEmpty) ...[
                  TextField(
                    controller: label,
                    enabled: !saving,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'ឈ្មោះ Link (ឧ. iPhone)'),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: days,
                    decoration: const InputDecoration(labelText: 'សុពលភាព'),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('៧ ថ្ងៃ')),
                      DropdownMenuItem(value: 30, child: Text('៣០ ថ្ងៃ')),
                      DropdownMenuItem(value: 90, child: Text('៩០ ថ្ងៃ')),
                    ],
                    onChanged: saving ? null : (v) => setState(() => days = v ?? 30),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: once,
                    onChanged: saving ? null : (v) => setState(() => once = v == true),
                    title: const Text('ប្រើបានតែម្តង'),
                  ),
                  TextField(
                    controller: password,
                    obscureText: true,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: 'ពាក្យសម្ងាត់របស់ខ្ញុំ *'),
                  ),
                ] else ...[
                  const Text('Link ថ្មី (បង្ហាញតែម្តងនេះប៉ុណ្ណោះ — សូមចម្លងឥឡូវ)', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  const Text('Link តែមួយ (Web + App) — ផ្ញើ Link នេះ', style: TextStyle(fontSize: 12)),
                  SelectableText(webUrl, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  TextButton.icon(
                    onPressed: () => copy(ctx, webUrl),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('ចម្លង Link (Web + App)'),
                  ),
                  if (appUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text('Link បម្រុងសម្រាប់ App (sdms://)', style: TextStyle(fontSize: 12)),
                    SelectableText(appUrl, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    TextButton.icon(
                      onPressed: () => copy(ctx, appUrl),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('ចម្លង Link បម្រុង'),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                const Text('រក្សាជាសម្ងាត់ — អ្នកណាមាន Link អាចចូលជាលោកបាន។', style: TextStyle(fontSize: 12)),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(webUrl.isEmpty ? 'បោះបង់' : 'បិទ'),
            ),
            if (webUrl.isEmpty)
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (password.text.isEmpty) {
                          return setState(() => error = 'សូមបញ្ចូលពាក្យសម្ងាត់របស់លោក');
                        }
                        setState(() {
                          saving = true;
                          error = '';
                        });
                        try {
                          final res = await ref.read(apiProvider).createLink(
                                label: label.text.trim(),
                                days: days,
                                once: once,
                                password: password.text,
                              );
                          setState(() {
                            webUrl = s(res['url']);
                            appUrl = s(res['app_url']);
                            saving = false;
                          });
                        } catch (e) {
                          setState(() {
                            error = e.toString();
                            saving = false;
                          });
                        }
                      },
                child: Text(saving ? 'កំពុងបង្កើត...' : 'បង្កើត Link'),
              ),
          ],
        ),
      ),
    );
    label.dispose();
    password.dispose();
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Link ចូលរបស់ខ្ញុំ (Deep link)',
      subtitle: 'បើក Link ដើម្បីចូលភ្លាមៗ ដោយមិនបាច់វាយពាក្យសម្ងាត់',
      trailing: IconButton.filledTonal(
        tooltip: 'បង្កើត Link ថ្មី',
        onPressed: _create,
        icon: const Icon(Icons.add_link_rounded),
      ),
      child: _loading && _rows.isEmpty
          ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
          : _error.isNotEmpty
              ? Text(_error, style: const TextStyle(color: AppColors.danger))
              : _rows.isEmpty
                  ? Text('មិនទាន់មាន Link', style: t.bodyMedium?.copyWith(color: AppColors.muted))
                  : Column(
                      children: [
                        for (final r in _rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    s(r['label']).isEmpty ? '-' : s(r['label']),
                                    overflow: TextOverflow.ellipsis,
                                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_linkStatus[s(r['status'])] != null)
                                  StatusBadge(_linkStatus[s(r['status'])]!.$1, tone: _linkStatus[s(r['status'])]!.$2),
                              ],
                            ),
                            subtitle: Text(
                              [
                                'ផុតកំណត់: ${formatDateTime(r['expires_at'])}',
                                if (s(r['last_used_at']).isNotEmpty) 'ប្រើចុងក្រោយ: ${formatDateTime(r['last_used_at'])}',
                                if (r['once'] == true) 'ប្រើបានតែម្តង',
                              ].join('\n'),
                              style: t.bodySmall?.copyWith(color: AppColors.muted),
                            ),
                            trailing: s(r['status']) == 'revoked'
                                ? null
                                : IconButton(
                                    tooltip: 'លុប Link',
                                    onPressed: () => _revoke(r),
                                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                  ),
                          ),
                      ],
                    ),
    );
  }
}
