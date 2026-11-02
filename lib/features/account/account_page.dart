import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_info.dart';
import '../../core/json.dart';
import '../../core/permission.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../state/theme_mode.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tab_header.dart';
import 'my_links_card.dart';

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
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.softOf(context),
                child: Text(initial, style: t.headlineSmall?.copyWith(color: AppColors.strong(context), fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fullName.isEmpty ? 'គណនីរបស់ខ្ញុំ' : fullName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(s(me['email']).isEmpty ? '-' : s(me['email']),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (role.isNotEmpty) _chip(context, Icons.shield_outlined, role, gold: isBoss(me)),
                        if (officeName.isNotEmpty) _chip(context, Icons.apartment_rounded, officeName),
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

        // the Big Boss has no office; he manages his own deep links instead
        if (isBoss(me)) ...[
          const MyLinksCard(),
          const SizedBox(height: 12),
        ] else
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
          title: 'រូបរាង',
          subtitle: 'ជ្រើសរើសរបៀបភ្លឺ ឬងងឹត',
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('ប្រព័ន្ធ')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('ភ្លឺ')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('ងងឹត')),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (v) => ref.read(themeModeProvider.notifier).set(v.first),
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _SimpleRow(icon: Icons.lock_outline_rounded, title: 'ប្តូរពាក្យសម្ងាត់', onTap: () => context.push('/account/password')),
              const Divider(height: 1),
              _SimpleRow(icon: Icons.logout_rounded, title: 'ចាកចេញ', danger: true, onTap: _logout),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(child: Text(AppInfo.versionText, style: t.bodySmall?.copyWith(color: AppColors.muted))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text, {bool gold = false}) {
    final dark = AppColors.isDark(context);
    final bg = gold ? (dark ? const Color(0xFF3A2F0F) : const Color(0xFFFBF3D5)) : AppColors.softOf(context);
    final fg = gold ? (dark ? const Color(0xFFE8D48A) : const Color(0xFF7A5F08)) : AppColors.strong(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// one tappable row of the security card
class _SimpleRow extends StatelessWidget {
  const _SimpleRow({required this.icon, required this.title, required this.onTap, this.danger = false});

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = danger ? (AppColors.isDark(context) ? const Color(0xFFFF8A94) : const Color(0xFFB02A37)) : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: danger ? FontWeight.w600 : FontWeight.w500, color: c))),
            if (!danger) const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
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
