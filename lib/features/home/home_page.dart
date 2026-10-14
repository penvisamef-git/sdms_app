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
import '../../widgets/tab_header.dart';
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

    final fullName = personName(me['user']).isNotEmpty ? personName(me['user']) : personName(user);
    final chain = [
      s(asObj(me['unit'])['name']),
      s(asObj(me['general_directorate'])['name']),
      s(asObj(me['department'])['name']),
      s(asObj(me['office'])['name']),
    ].where((e) => e.isNotEmpty).join(' › ');
    final isNow = _month == currentMonthValue();

    return Column(
      children: [
        // ----- fixed header: greeting + month; only the part below scrolls -----
        TabHeader(
          title: fullName.isEmpty ? 'ទិន្នន័យសង្ខេប' : 'សួស្តី $fullName',
          subtitle: chain.isEmpty ? 'ទិន្នន័យសង្ខេបនៃឯកសាររបស់អ្នក' : chain,
          actions: [
            if (!isNow)
              IconButton(
                tooltip: 'ខែនេះ',
                onPressed: () => _setMonth(currentMonthValue()),
                icon: const Icon(Icons.today_rounded),
              ),
          ],
          bottom: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'ខែមុន',
                onPressed: () => _setMonth(shiftMonth(_month, -1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: _pickMonth,
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),
                  label: Text(monthLabel(_month), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'ខែបន្ទាប់',
                onPressed: () => _setMonth(shiftMonth(_month, 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'រាប់តាម: ${_dateFields.firstWhere((o) => o.value == _dateField).label}',
                onPressed: _pickField,
                icon: Badge(
                  isLabelVisible: _dateField != 'created_date',
                  smallSize: 8,
                  child: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                if (_error.isNotEmpty && data == null)
                  ErrorState(_error, onRetry: () => _load(force: true))
                else if (data == null)
                  const SkeletonHome()
                else ...[
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error, style: const TextStyle(color: AppColors.danger)),
                    ),

                  // ----- needs action now -----
                  _HeroCard(
                    waiting: asInt(transfers['waiting_to_receive']),
                    onHand: asInt(transfers['on_hand']),
                    onTap: canIn ? () => context.go('/document/in') : null,
                  ),
                  const SizedBox(height: 28),

                  // ----- the selected month -----
                  _SectionTitle('សង្ខេបប្រចាំខែ', trailing: monthLabel(_month)),
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.description_outlined,
                          color: AppColors.primary,
                          label: 'ឯកសារសរុប',
                          value: asInt(docs['total']),
                          sub: 'ចេញ ${formatNumber(docs['out'])} · ចូល ${formatNumber(docs['in'])}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tile(
                          icon: Icons.fiber_new_rounded,
                          color: AppColors.info,
                          label: 'ឯកសារថ្មី',
                          value: asInt(asObj(data['new_documents'])['total']),
                          sub: 'ស្ថានភាព ថ្មី',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.send_rounded,
                          color: AppColors.warn,
                          label: 'បានផ្ញើ',
                          value: asInt(transfers['sent_this_month']),
                          sub: 'ផ្ញើ/បញ្ជូនបន្ត',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tile(
                          icon: Icons.check_circle_outline_rounded,
                          color: AppColors.done,
                          label: 'បានបញ្ចប់',
                          value: asInt(transfers['done_this_month']),
                          sub: 'បិទដំណើរការ',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Tile(
                    wide: true,
                    icon: Icons.undo_rounded,
                    color: AppColors.danger,
                    label: 'រុញត្រឡប់មកខ្ញុំ',
                    value: asInt(transfers['returned_to_me_this_month']),
                    sub: 'ឯកសារដែលត្រូវបានរុញត្រឡប់មកខ្ញុំ',
                  ),
                  const SizedBox(height: 28),

                  // ----- charts -----
                  _SectionTitle('ស្ថិតិ'),
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    title: 'ឯកសារតាមថ្ងៃ',
                    subtitle: '${monthLabel(_month)} · សរុប ${formatNumber(docs['total'])} ឯកសារ',
                    child: asInt(docs['total']) == 0
                        ? const EmptyState('គ្មានឯកសារក្នុងខែនេះ')
                        : DayColumns(days: asList(docs['by_day'])),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    padding: const EdgeInsets.all(20),
                    title: 'ការបែងចែក',
                    subtitle: 'តាមស្ថានភាព និងប្រភពឯកសារ',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MiniLabel('ស្ថានភាព'),
                        StackBar(parts: [
                          StackPart(docStatus['new']!.label, asInt(asObj(docs['by_status'])['new']), AppColors.info),
                          StackPart(docStatus['process']!.label, asInt(asObj(docs['by_status'])['process']), AppColors.warn),
                          StackPart(docStatus['close']!.label, asInt(asObj(docs['by_status'])['close']), AppColors.done),
                        ]),
                        const SizedBox(height: 24),
                        _MiniLabel('ប្រភព'),
                        StackBar(parts: [
                          StackPart('ចេញ · បង្កើតដោយការិយាល័យខ្ញុំ', asInt(docs['out']), AppColors.primary),
                          StackPart('ចូល · ទទួលបាន', asInt(docs['in']), AppColors.other),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  _NewDocumentsCard(month: _month, dateField: _dateField, refreshKey: _refreshKey),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// small grey heading above a group of cards
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        children: [
          Expanded(child: Text(text, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (trailing != null) Text(trailing!, style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700)),
      );
}

/// Big green card: what needs action now (waiting to receive / on hand).
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.waiting, required this.onHand, this.onTap});

  final int waiting;
  final int onHand;
  final VoidCallback? onTap;

  Widget _stat(BuildContext context, IconData icon, String label, int value, String sub) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(color: Colors.white70, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(formatNumber(value), style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.05)),
          const SizedBox(height: 6),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(26),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryDark, AppColors.primary]),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stat(context, Icons.move_to_inbox_rounded, 'រង់ចាំទទួល', waiting, waiting > 0 ? 'ចុចដើម្បីពិនិត្យ' : 'គ្មានឯកសារត្រូវទទួល'),
                Container(width: 1, height: 84, margin: const EdgeInsets.symmetric(horizontal: 18), color: Colors.white24),
                _stat(context, Icons.schedule_rounded, 'កំពុងកាន់', onHand, 'បានទទួល មិនទាន់បញ្ជូនបន្ត'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.sub,
    this.wide = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int value;
  final String? sub;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final chip = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Icon(icon, size: 22, color: color),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w600)),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Text(sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ],
    );
    final number = Text(formatNumber(value), style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: wide
          ? Row(
              children: [
                chip,
                const SizedBox(width: 14),
                Expanded(child: texts),
                const SizedBox(width: 10),
                number,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                chip,
                const SizedBox(height: 14),
                number,
                const SizedBox(height: 4),
                texts,
              ],
            ),
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
      padding: const EdgeInsets.all(20),
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
                          for (final (i, d) in _rows.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _open(d),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
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
