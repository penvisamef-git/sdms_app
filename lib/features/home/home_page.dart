import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/permission.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/select_sheet.dart';
import '../documents/doc_helpers.dart';
import 'home_charts.dart';

const _dateFields = [
  Option('created_date', 'ថ្ងៃបង្កើត'),
  Option('date_in', 'ថ្ងៃចូល'),
  Option('date_registration_document', 'ថ្ងៃចុះបញ្ជី'),
  Option('date_sign', 'ថ្ងៃចុះហត្ថលេខា'),
  Option('date_sent', 'ថ្ងៃផ្ញើ'),
];

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _month = currentMonthValue();
  String _dateField = 'created_date';
  Json? _data;
  String _error = '';
  int _seq = 0;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final mine = ++_seq;
    if (force) {
      ref.read(apiClientProvider).clearCache();
    } else {
      // the last answer for this month, on screen at once; the new one replaces it quietly
      final saved = ref.read(apiProvider).peekHomeSummary(month: _month, dateField: _dateField);
      if (saved != null) _data = asObj(saved['data']);
    }
    setState(() => _error = '');
    try {
      final res = await ref.read(apiProvider).homeSummary(month: _month, dateField: _dateField);
      if (mine != _seq || !mounted) return;
      setState(() {
        _data = asObj(res['data']);
        if (force) _refreshKey++;
      });
    } catch (e) {
      if (mine == _seq && mounted) setState(() => _error = e.toString());
    }
  }

  void _setMonth(String m) {
    if (m == _month) return;
    setState(() => _month = m);
    _load();
  }

  Future<void> _pickMonth() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MonthSheet(value: _month),
    );
    if (r != null) _setMonth(r);
  }

  Future<void> _pickField() async {
    final r = await showSelectSheet(
      context,
      title: 'រាប់តាម',
      options: _dateFields,
      selected: _dateField,
      allowClear: false,
    );
    if (r != null && r.isNotEmpty && r != _dateField) {
      setState(() => _dateField = r);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final canIn = canAccess(user, Access.docIn);
    final data = _data;
    final docs = asObj(data?['documents']);
    final transfers = asObj(data?['transfers']);
    final me = asObj(data?['me']);
    final t = Theme.of(context).textTheme;

    final fullName = personName(me['user']).isNotEmpty ? personName(me['user']) : personName(user);
    final chain = [
      s(asObj(me['unit'])['name']),
      s(asObj(me['general_directorate'])['name']),
      s(asObj(me['department'])['name']),
      s(asObj(me['office'])['name']),
    ].where((e) => e.isNotEmpty).join(' › ');

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ----- greeting -----
          Text(fullName.isEmpty ? 'ទិន្នន័យសង្ខេប' : 'សួស្តី $fullName',
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(chain.isEmpty ? 'ទិន្នន័យសង្ខេបនៃឯកសាររបស់អ្នក' : chain,
              style: t.bodySmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 14),

          // ----- filters -----
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => _setMonth(shiftMonth(_month, -1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _pickMonth,
                  child: Text(monthLabel(_month), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _setMonth(shiftMonth(_month, 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickField,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(
                    'រាប់តាម: ${_dateFields.firstWhere((o) => o.value == _dateField).label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _month == currentMonthValue() ? null : () => _setMonth(currentMonthValue()),
                child: const Text('ខែនេះ'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_error.isNotEmpty && data == null)
            ErrorState(_error, onRetry: () => _load(force: true))
          else if (data == null)
            const SkeletonHome()
          else ...[
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error, style: const TextStyle(color: AppColors.danger)),
              ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ----- needs action now -----
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          hero: true,
                          icon: Icons.move_to_inbox_rounded,
                          label: 'រង់ចាំទទួល',
                          value: asInt(transfers['waiting_to_receive']),
                          sub: asInt(transfers['waiting_to_receive']) > 0 ? 'ចុចដើម្បីពិនិត្យ' : 'គ្មានឯកសារត្រូវទទួល',
                          onTap: canIn ? () => context.go('/document/in') : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Tile(
                          icon: Icons.schedule_rounded,
                          label: 'កំពុងកាន់',
                          value: asInt(transfers['on_hand']),
                          sub: 'បានទទួល មិនទាន់បញ្ជូនបន្ត',
                          onTap: canIn ? () => context.go('/document/in') : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ----- the selected month -----
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.description_outlined,
                          label: 'ឯកសារសរុប',
                          value: asInt(docs['total']),
                          sub: 'ចេញ ${formatNumber(docs['out'])} · ចូល ${formatNumber(docs['in'])}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Tile(
                          icon: Icons.fiber_new_rounded,
                          label: 'ឯកសារថ្មី',
                          value: asInt(asObj(data['new_documents'])['total']),
                          sub: 'ស្ថានភាព ថ្មី',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.send_rounded,
                          label: 'បានផ្ញើ',
                          value: asInt(transfers['sent_this_month']),
                          sub: 'ផ្ញើ/បញ្ជូនបន្ត',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Tile(
                          icon: Icons.undo_rounded,
                          label: 'រុញត្រឡប់មកខ្ញុំ',
                          value: asInt(transfers['returned_to_me_this_month']),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Tile(
                          icon: Icons.check_rounded,
                          label: 'បានបញ្ចប់',
                          value: asInt(transfers['done_this_month']),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ----- charts -----
                  SectionCard(
                    title: 'ឯកសារតាមថ្ងៃ',
                    subtitle: '${monthLabel(_month)} · សរុប ${formatNumber(docs['total'])} ឯកសារ',
                    child: asInt(docs['total']) == 0
                        ? const EmptyState('គ្មានឯកសារក្នុងខែនេះ')
                        : DayColumns(days: asList(docs['by_day'])),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'ស្ថានភាពឯកសារ',
                    subtitle: 'ចែកតាមស្ថានភាព',
                    child: StackBar(parts: [
                      StackPart(docStatus['new']!.label, asInt(asObj(docs['by_status'])['new']), AppColors.info),
                      StackPart(docStatus['process']!.label, asInt(asObj(docs['by_status'])['process']), AppColors.warn),
                      StackPart(docStatus['close']!.label, asInt(asObj(docs['by_status'])['close']), AppColors.done),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'ចូល និង ចេញ',
                    subtitle: 'ប្រភពឯកសារ',
                    child: StackBar(parts: [
                      StackPart('ចេញ · បង្កើតដោយការិយាល័យខ្ញុំ', asInt(docs['out']), AppColors.primary),
                      StackPart('ចូល · ទទួលបាន', asInt(docs['in']), AppColors.other),
                    ]),
                  ),
                  const SizedBox(height: 12),

                  _NewDocumentsCard(month: _month, dateField: _dateField, refreshKey: _refreshKey),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'ទីតាំងរបស់ខ្ញុំ',
                    subtitle: 'ការិយាល័យ → អង្គភាព',
                    child: _OfficeChain(me: me),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.hero = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final String? sub;
  final bool hero;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = hero ? Colors.white : null;
    final subColor = hero ? Colors.white70 : AppColors.muted;
    return Material(
      color: hero ? AppColors.primary : Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: hero ? Colors.white : AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelMedium?.copyWith(color: fg ?? AppColors.muted, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(formatNumber(value), style: t.headlineMedium?.copyWith(color: fg, fontWeight: FontWeight.w800)),
              if (sub != null)
                Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: subColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfficeChain extends StatelessWidget {
  const _OfficeChain({required this.me});

  final Json me;

  @override
  Widget build(BuildContext context) {
    const levels = [
      ('unit', 'អង្គភាព'),
      ('general_directorate', 'អគ្គនាយកដ្ឋាន'),
      ('department', 'នាយកដ្ឋាន'),
      ('office', 'ការិយាល័យ'),
    ];
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < levels.length; i++)
          Padding(
            padding: EdgeInsets.only(left: i * 14.0, top: 6, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: i == levels.length - 1 ? AppColors.primary : AppColors.other,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(levels[i].$2, style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      Text(
                        s(asObj(me[levels[i].$1])['name']).isEmpty ? '-' : s(asObj(me[levels[i].$1])['name']),
                        style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (s(asObj(me[levels[i].$1])['name_in_eng']).isNotEmpty)
                        Text(s(asObj(me[levels[i].$1])['name_in_eng']),
                            style: t.bodySmall?.copyWith(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthSheet extends StatefulWidget {
  const _MonthSheet({required this.value});

  final String value;

  @override
  State<_MonthSheet> createState() => _MonthSheetState();
}

class _MonthSheetState extends State<_MonthSheet> {
  late int _year = int.parse(widget.value.split('-')[0]);

  @override
  Widget build(BuildContext context) {
    final selMonth = int.parse(widget.value.split('-')[1]);
    final selYear = int.parse(widget.value.split('-')[0]);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
                Text('$_year', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 2.2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var m = 1; m <= 12; m++)
                  ChoiceChip(
                    label: SizedBox(width: double.infinity, child: Text(khMonths[m - 1], textAlign: TextAlign.center)),
                    selected: m == selMonth && _year == selYear,
                    onSelected: (_) => Navigator.pop(context, '$_year-${m.toString().padLeft(2, '0')}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Latest new documents, paged 5 at a time, filter in / out / all.
class _NewDocumentsCard extends ConsumerStatefulWidget {
  const _NewDocumentsCard({required this.month, required this.dateField, required this.refreshKey});

  final String month;
  final String dateField;
  final int refreshKey;

  @override
  ConsumerState<_NewDocumentsCard> createState() => _NewDocumentsCardState();
}

class _NewDocumentsCardState extends ConsumerState<_NewDocumentsCard> {
  String _box = 'all';
  bool _allTime = false;
  int _page = 1;
  List<Json> _rows = [];
  int _total = 0;
  int _totalPages = 1;
  bool _loading = true;
  String _error = '';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _NewDocumentsCard old) {
    super.didUpdateWidget(old);
    if (old.month != widget.month || old.dateField != widget.dateField) {
      _page = 1;
      _load();
    } else if (old.refreshKey != widget.refreshKey) {
      _load();
    }
  }

  Future<void> _load() async {
    final mine = ++_seq;
    final params = <String, dynamic>{
      'month': widget.month,
      'date_field': widget.dateField,
      'box': _box,
      'page': _page,
      'limit': 5,
      if (_allTime) 'all_time': 'true',
    };
    final saved = ref.read(apiProvider).peekHomeNewDocuments(params);
    if (saved != null) {
      final pg = asObj(saved['pagination']);
      _rows = asList(saved['data']);
      _total = asInt(pg['total']);
      _totalPages = asInt(pg['totalPages']).clamp(1, 100000);
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ref.read(apiProvider).homeNewDocuments(params);
      if (mine != _seq || !mounted) return;
      final pg = asObj(res['pagination']);
      setState(() {
        _rows = asList(res['data']);
        _total = asInt(pg['total']);
        _totalPages = asInt(pg['totalPages']).clamp(1, 100000);
      });
    } catch (e) {
      if (mine == _seq && mounted) setState(() => _error = e.toString());
    } finally {
      if (mine == _seq && mounted) setState(() => _loading = false);
    }
  }

  void _change({String? box, bool? allTime, int? page}) {
    setState(() {
      if (box != null) _box = box;
      if (allTime != null) _allTime = allTime;
      _page = page ?? 1;
    });
    _load();
  }

  void _open(Json d) {
    final user = ref.read(authProvider).user;
    // open it in a list this role may use (an "in" user cannot use /document/out)
    final target = docBoxFor(user, s(d['document_progress']));
    if (target != null) context.push('/document/$target/view/${s(d['_id'])}');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'ឯកសារថ្មី',
      subtitle: '${_allTime ? 'គ្រប់ពេលវេលា' : monthLabel(widget.month)} · ${formatNumber(_total)} ឯកសារ',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('ទាំងអស់')),
                    ButtonSegment(value: 'out', label: Text('ចេញ')),
                    ButtonSegment(value: 'in', label: Text('ចូល')),
                  ],
                  selected: {_box},
                  onSelectionChanged: (v) => _change(box: v.first),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _allTime,
            title: const Text('គ្រប់ខែ'),
            onChanged: (v) => _change(allTime: v ?? false),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: 1,
            child: _error.isNotEmpty
                ? Text(_error, style: const TextStyle(color: AppColors.danger))
                : _rows.isEmpty
                    ? (_loading ? const SkeletonLines(lines: 5) : const EmptyState('គ្មានឯកសារថ្មី'))
                    : Column(
                        children: [
                          for (final d in _rows)
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _open(d),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(s(d['code_of_document']).isEmpty ? '-' : s(d['code_of_document']),
                                                  style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                                              StatusBadge(
                                                s(d['document_progress']) == 'out' ? 'ចេញ' : 'ចូល',
                                                tone: s(d['document_progress']) == 'out' ? Tone.info : Tone.neutral,
                                              ),
                                            ],
                                          ),
                                          Text(s(d['objective']).isEmpty ? '-' : s(d['objective']),
                                              maxLines: 2, overflow: TextOverflow.ellipsis),
                                          Text(
                                            [
                                              s(asObj(d['document_type_id'])['name']),
                                              s(asObj(d['status_of_process_id'])['name']),
                                              s(asObj(d['office_id_open'])['name']),
                                            ].where((e) => e.isNotEmpty).join(' · '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.bodySmall?.copyWith(color: AppColors.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(formatDate(d['created_date']), style: t.bodySmall?.copyWith(color: AppColors.muted)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
          if (_totalPages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page <= 1 || _loading ? null : () => _change(page: _page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_page / $_totalPages'),
                IconButton(
                  onPressed: _page >= _totalPages || _loading ? null : () => _change(page: _page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
