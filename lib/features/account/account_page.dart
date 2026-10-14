import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_info.dart';
import '../../core/json.dart';
import '../../core/permission.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  Json _profile = {};
  Json? _chain;
  bool _loading = true;

  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    final r = await Future.wait<Json?>([
      api.profile().then<Json?>((v) => v).catchError((_) => null),
      api.myOffice().then<Json?>((v) => v).catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      final d = asObj(r[0]?['data']);
      _profile = d['user'] is Map ? asObj(d['user']) : d;
      _chain = r[1] == null ? null : asObj(r[1]!['data']);
      _loading = false;
    });
  }

  Future<void> _changePassword() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    if (_old.text.isEmpty) return setState(() => _error = 'សូមបញ្ចូលពាក្យសម្ងាត់ចាស់');
    if (_new.text.isEmpty) return setState(() => _error = 'សូមបញ្ចូលពាក្យសម្ងាត់ថ្មី');
    if (_new.text.length < 8) return setState(() => _error = 'ពាក្យសម្ងាត់ថ្មីត្រូវមានយ៉ាងតិច ៨ តួអក្សរ');
    if (_new.text != _confirm.text) return setState(() => _error = 'ពាក្យសម្ងាត់បញ្ជាក់មិនត្រូវគ្នា');

    setState(() => _saving = true);
    try {
      final res = await ref.read(apiProvider).changePassword(_old.text, _new.text);
      if (!mounted) return;
      showSnack(context, s(res['message']).isNotEmpty ? s(res['message']) : 'បានប្តូរពាក្យសម្ងាត់ថ្មី!');
      _old.clear();
      _new.clear();
      _confirm.clear();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final ok = await confirmDialog(
      context,
      title: 'ចាកចេញពីគណនី?',
      message: 'តើអ្នកពិតជាចង់ចាកចេញមែនទេ?',
      confirmText: 'ចាកចេញ',
      danger: true,
    );
    if (ok) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final login = ref.watch(authProvider).user ?? {};
    final me = {...login, ..._profile};
    final t = Theme.of(context).textTheme;
    final fullName = personName(me);
    final initial = Characters(s(me['firstname']).isNotEmpty ? s(me['firstname']) : (s(me['email']).isEmpty ? '?' : s(me['email']))).first.toUpperCase();
    final officeName = s(asObj(_chain?['office'])['name']).isNotEmpty
        ? s(asObj(_chain?['office'])['name'])
        : s(asObj(me['office_id'])['name']);
    final role = roleOf(me);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ----- hero -----
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primary],
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(initial, style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName.isEmpty ? 'គណនីរបស់ខ្ញុំ' : fullName,
                        style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    Text(s(me['email']).isEmpty ? '-' : s(me['email']), style: t.bodySmall?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (role.isNotEmpty) _chip(Icons.shield_outlined, role),
                        if (officeName.isNotEmpty) _chip(Icons.apartment_rounded, officeName),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        SectionCard(
          title: 'ព័ត៌មានផ្ទាល់ខ្លួន',
          child: Column(
            children: [
              InfoRow('គោត្តនាម', s(me['firstname'])),
              InfoRow('នាម', s(me['lastname'])),
              InfoRow('អ៊ីមែល', s(me['email'])),
              InfoRow('លេខទំនាក់ទំនង', s(me['contact'])),
              InfoRow('តួនាទី', role),
            ],
          ),
        ),
        const SizedBox(height: 12),

        SectionCard(
          title: 'ទីតាំងការងារ',
          child: _loading && _chain == null
              ? const Text('កំពុងផ្ទុក...', style: TextStyle(color: AppColors.muted))
              : Column(
                  children: [
                    for (final (i, l) in const [
                      ('unit', 'អង្គភាព'),
                      ('general_directorate', 'អគ្គនាយកដ្ឋាន'),
                      ('department', 'នាយកដ្ឋាន'),
                      ('office', 'ការិយាល័យ'),
                    ].indexed)
                      Padding(
                        padding: EdgeInsets.only(left: i * 14.0, top: 6, bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: CircleAvatar(radius: 4, backgroundColor: i == 3 ? AppColors.primary : AppColors.other),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.$2, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                                  Text(
                                    s(asObj(_chain?[l.$1])['name']).isEmpty ? '-' : s(asObj(_chain?[l.$1])['name']),
                                    style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (s(asObj(_chain?[l.$1])['name_in_eng']).isNotEmpty)
                                    Text(s(asObj(_chain?[l.$1])['name_in_eng']),
                                        style: t.bodySmall?.copyWith(color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),

        SectionCard(
          title: 'ប្តូរពាក្យសម្ងាត់',
          subtitle: 'ឧបករណ៍ផ្សេងទៀតនឹងត្រូវចូលគណនីម្តងទៀត (យ៉ាងតិច ៨ តួអក្សរ)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pwd(_old, 'ពាក្យសម្ងាត់ចាស់'),
              const SizedBox(height: 12),
              _pwd(_new, 'ពាក្យសម្ងាត់ថ្មី'),
              const SizedBox(height: 12),
              _pwd(_confirm, 'បញ្ជាក់ពាក្យសម្ងាត់ថ្មី'),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _show = !_show),
                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  label: Text(_show ? 'លាក់' : 'បង្ហាញ'),
                ),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error, style: const TextStyle(color: AppColors.danger)),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _changePassword,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.key_rounded),
                label: const Text('ប្តូរពាក្យសម្ងាត់'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
          ),
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('ចាកចេញ'),
        ),
        const SizedBox(height: 16),
        Center(child: Text(AppInfo.versionText, style: t.bodySmall?.copyWith(color: AppColors.muted))),
      ],
    );
  }

  Widget _chip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 4),
            Flexible(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _pwd(TextEditingController c, String label) => TextField(
        controller: c,
        enabled: !_saving,
        obscureText: !_show,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.lock_outline_rounded)),
      );
}
