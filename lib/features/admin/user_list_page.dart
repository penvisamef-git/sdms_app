import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/permission.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/select_sheet.dart';
import 'crud_page.dart';

/// Users: add / edit / delete, switch "can use the mobile app", reset password.
class UserListPage extends ConsumerWidget {
  const UserListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CrudPage(
      title: 'អ្នកប្រើប្រាស់',
      resource: (a) => a.users,
      searchKeys: const ['firstname', 'lastname', 'email', 'contact'],
      rowTitle: personName,
      rowSubtitle: (r) => [
        s(r['email']),
        s(asObj(r['office_id'])['name']),
        s(r['role'] is String ? r['role'] : asObj(r['role'])['name']),
      ].where((e) => e.isNotEmpty).join(' · '),
      canDelete: (row, me) => s(row['_id']) != s(me?['_id']),
      rowActions: (row) => [
        // a deep link for everybody except a super admin account
        if (_roleName(row) != Role.superAdmin && row['is_super_admin'] != true)
          RowAction('បង្កើត Link ចូល (Deep link)', Icons.link_rounded, (ctx, ref) => _link(ctx, ref, row)),
        RowAction('កំណត់ពាក្យសម្ងាត់ថ្មី', Icons.key_rounded, (ctx, ref) => _reset(ctx, ref, row)),
      ],
      fields: [
        const FieldDef('firstname', 'គោត្តនាម', required: true),
        const FieldDef('lastname', 'នាម', required: true),
        const FieldDef('email', 'អ៊ីមែល', type: FieldType.email, required: true),
        const FieldDef('contact', 'លេខទំនាក់ទំនង', type: FieldType.tel, required: true),
        const FieldDef('password', 'ពាក្យសម្ងាត់', type: FieldType.password, required: true, createOnly: true),
        const FieldDef('organization', 'ស្ថាប័ន/អង្គភាព', required: true),
        const FieldDef('job_title', 'មុខតំណែង'),
        FieldDef(
          'office_id',
          'ការិយាល័យ (មិនត្រូវការសម្រាប់ថ្នាក់ដឹកនាំ)',
          type: FieldType.select,
          required: false,
          hint: '-- ជ្រើសរើសការិយាល័យ --',
          options: (a) async {
            final res = await a.offices.all();
            return [
              for (final o in asList(res['data']))
                Option(
                  s(o['_id']),
                  s(asObj(o['department_id'])['name']).isEmpty
                      ? s(o['name'])
                      : '${s(o['name'])} (${s(asObj(o['department_id'])['name'])})',
                ),
            ];
          },
        ),
        FieldDef(
          'role',
          'ក្រុមសិទ្ធិ',
          type: FieldType.select,
          required: true,
          hint: '-- ជ្រើសរើសក្រុមសិទ្ធិ --',
          options: (a) async => [for (final r in Role.all) Option(r, r)],
        ),
        const FieldDef('note', 'កំណត់សម្គាល់', type: FieldType.textarea),
      ],
    );
  }

  static String _roleName(Json row) => row['role'] is String ? s(row['role']) : s(asObj(row['role'])['name']);

  /// Admin: make a new deep link for this user. The link is shown only once.
  static Future<void> _link(BuildContext context, WidgetRef ref, Json row) async {
    final label = TextEditingController();
    int days = 90;
    bool once = false;
    bool reset = true;
    String error = '';
    bool saving = false;
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
          title: const Text('បង្កើត Link ចូល (Deep link)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${personName(row)} (${s(row['email'])})', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
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
                    onChanged: saving ? null : (v) => setState(() => days = v ?? 90),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: once,
                    onChanged: saving ? null : (v) => setState(() => once = v == true),
                    title: const Text('ប្រើបានតែម្តង'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: reset,
                    onChanged: saving ? null : (v) => setState(() => reset = v == true),
                    title: const Text('លុប Link ចាស់ទាំងអស់ (ឧបករណ៍ដែលចូលដោយ Link ចាស់នឹងត្រូវចាកចេញ)'),
                  ),
                ] else ...[
                  const Text('Link ថ្មី (បង្ហាញតែម្តងនេះប៉ុណ្ណោះ — សូមចម្លងឥឡូវ)', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  const Text('Web', style: TextStyle(fontSize: 12)),
                  SelectableText(webUrl, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  TextButton.icon(
                    onPressed: () => copy(ctx, webUrl),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('ចម្លង Link Web'),
                  ),
                  if (appUrl.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Text('App', style: TextStyle(fontSize: 12)),
                    SelectableText(appUrl, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    TextButton.icon(
                      onPressed: () => copy(ctx, appUrl),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('ចម្លង Link App'),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                const Text(
                  'អ្នកណាមាន Link នេះ អាចចូលជាអ្នកប្រើប្រាស់នេះបាន។ សូមផ្ញើតាមបណ្តាញសុវត្ថិភាព។',
                  style: TextStyle(fontSize: 12),
                ),
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
                        setState(() {
                          saving = true;
                          error = '';
                        });
                        try {
                          final res = await ref.read(apiProvider).createUserLink(
                                userId: s(row['_id']),
                                label: label.text.trim(),
                                days: days,
                                once: once,
                                reset: reset,
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
  }

  static Future<void> _reset(BuildContext context, WidgetRef ref, Json row) async {
    final pwd = TextEditingController();
    final confirm = TextEditingController();
    String error = '';
    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('កំណត់ពាក្យសម្ងាត់ថ្មី'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${personName(row)} (${s(row['email'])})', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                TextField(
                  controller: pwd,
                  obscureText: true,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'ពាក្យសម្ងាត់ថ្មី *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirm,
                  obscureText: true,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'បញ្ជាក់ពាក្យសម្ងាត់ *'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'អ្នកប្រើប្រាស់នឹងត្រូវចាកចេញពីគ្រប់ឧបករណ៍ ហើយត្រូវចូលគណនីម្តងទៀត។',
                  style: TextStyle(fontSize: 12),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('បោះបង់')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (pwd.text.isEmpty) return setState(() => error = 'សូមបញ្ចូលពាក្យសម្ងាត់ថ្មី');
                      if (pwd.text != confirm.text) return setState(() => error = 'ពាក្យសម្ងាត់បញ្ជាក់មិនត្រូវគ្នា');
                      setState(() {
                        saving = true;
                        error = '';
                      });
                      try {
                        final res = await ref.read(apiProvider).resetPassword(s(row['_id']), pwd.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          showSnack(context, s(res['message']).isNotEmpty ? s(res['message']) : 'បានកំណត់ពាក្យសម្ងាត់ថ្មី!');
                        }
                      } catch (e) {
                        setState(() {
                          error = e.toString();
                          saving = false;
                        });
                      }
                    },
              child: const Text('រក្សាទុក'),
            ),
          ],
        ),
      ),
    );
    pwd.dispose();
    confirm.dispose();
  }
}
