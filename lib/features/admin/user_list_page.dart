import 'package:flutter/material.dart';
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
          'ការិយាល័យ',
          type: FieldType.select,
          required: true,
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
        const FieldDef(
          'can_login_in_app',
          'អនុញ្ញាតឱ្យចូលប្រើក្នុង Mobile App',
          type: FieldType.checkbox,
        ),
        const FieldDef('note', 'កំណត់សម្គាល់', type: FieldType.textarea),
      ],
    );
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
