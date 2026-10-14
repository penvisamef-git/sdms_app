import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_info.dart';
import '../../core/json.dart';
import '../../core/permission.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tab_header.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  Json _profile = {};
  Json? _chain;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = ref.read(apiProvider).peekMyOffice();
    if (cached != null) _chain = asObj(cached['data']);
    _load();
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

    return Column(
      children: [
        const TabHeader(title: 'គណនី', subtitle: 'ព័ត៌មាន និងសុវត្ថិភាពគណនីរបស់អ្នក'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
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
              _DetailRow(Icons.person_outline_rounded, 'គោត្តនាម', s(me['firstname'])),
              _DetailRow(Icons.badge_outlined, 'នាម', s(me['lastname'])),
              _DetailRow(Icons.mail_outline_rounded, 'អ៊ីមែល', s(me['email'])),
              _DetailRow(Icons.phone_outlined, 'លេខទំនាក់ទំនង', s(me['contact'])),
              _DetailRow(Icons.shield_outlined, 'តួនាទី', role, last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SectionCard(
          title: 'ទីតាំងការងារ',
          child: _loading && _chain == null
              ? const SkeletonLines(lines: 4)
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
          title: 'សុវត្ថិភាព',
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: _ActionRow(
            icon: Icons.lock_reset_rounded,
            title: 'ប្តូរពាក្យសម្ងាត់',
            subtitle: 'ផ្លាស់ប្តូរពាក្យសម្ងាត់ចូលគណនីរបស់អ្នក',
            onTap: () => context.push('/account/password'),
          ),
        ),
        const SizedBox(height: 20),

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
          ),
        ),
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
}

/// icon box + label + value; every row has the same height and alignment
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value, {this.last = false});

  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                    const SizedBox(height: 2),
                    Text(value.trim().isEmpty ? '-' : value, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }
}

/// a row that opens another page (icon, title, small text and a chevron)
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
