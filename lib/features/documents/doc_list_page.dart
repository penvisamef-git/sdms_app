import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tab_header.dart';
import '../../widgets/select_sheet.dart';
import 'doc_helpers.dart';

const _searchKeys = ['code_of_document', 'number_document', 'objective'];
const _pageSize = 15;

/// box "in"  : transfers sent to me / my office  (GET /document-transfer/inbox)
/// box "out" : documents my office created        (GET /document?box=out)
class DocListPage extends ConsumerStatefulWidget {
  const DocListPage({super.key, required this.box, this.boss});

  final String box;

  /// Big Boss only: 'inbox' = waiting for him · 'history' = already handled. null = normal user.
  final String? boss;

  @override
  ConsumerState<DocListPage> createState() => _DocListPageState();
}

class _DocListPageState extends ConsumerState<DocListPage> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();
  Timer? _debounce;

  final List<Json> _rows = [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  String _error = '';
  String _search = '';
  String _status = '';

  bool get _isIn => widget.box == 'in';
  bool get _isBoss => widget.boss != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    final api = ref.read(apiProvider);
    if (reset) {
      _page = 1;
    }
    final params = <String, dynamic>{'page': _page, 'limit': _pageSize};
    if (_isIn) {
      if (_isBoss) {
        params['status'] = widget.boss == 'inbox' ? 'pending,received' : 'returned,forwarded,done';
      } else if (_status.isNotEmpty) {
        params['status'] = _status;
      }
    } else {
      params['box'] = 'out';
      if (_status.isNotEmpty) params['status'] = _status;
      if (_search.isNotEmpty) {
        params['q'] = _search;
        params['q_key'] = _searchKeys;
      }
    }
    // the last first page, on screen at once; the new answer replaces it quietly
    if (reset && _rows.isEmpty) {
      final saved = _isIn ? api.peekInbox(params) : api.peekDocumentList(params);
      if (saved != null) {
        final pg = asObj(saved['pagination']);
        _rows.addAll(asList(saved['data']));
        _totalPages = asInt(pg['totalPages']).clamp(1, 100000);
        _total = asInt(pg['total']);
      }
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = _isIn ? await api.inbox(params) : await api.documentList(params);
      final pg = asObj(res['pagination']);
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(asList(res['data']));
        _totalPages = asInt(pg['totalPages']).clamp(1, 100000);
        _total = asInt(pg['total']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadMore() {
    if (_loading || _page >= _totalPages) return;
    _page++;
    _load();
  }

  Future<void> _refresh() async {
    ref.read(apiClientProvider).clearCache();
    await _load(reset: true);
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final kw = v.trim();
      if (kw == _search) return;
      setState(() => _search = kw);
      if (!_isIn) _load(reset: true); // inbox has no search API: filter the loaded rows below
    });
  }

  List<Json> get _visible {
    if (!_isIn || _search.isEmpty) return _rows;
    final kw = _search.toLowerCase();
    return _rows.where((t) {
      final d = asObj(t['document_id']);
      return _searchKeys.any((k) => s(d[k]).toLowerCase().contains(kw));
    }).toList();
  }

  Future<void> _open(String? id) async {
    if (id == null || id.isEmpty) return;
    await context.push('/document/${widget.box}/view/$id');
    if (mounted) _load(reset: true);
  }

  Future<void> _create() async {
    final saved = await context.push<bool>('/document/out/create');
    if (saved == true && mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;

    return Scaffold(
      floatingActionButton: _isIn
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('ឯកសារថ្មី'),
              shape: const StadiumBorder(),
              backgroundColor: AppColors.isDark(context) ? AppColors.darkAccent : AppColors.primaryDark,
              foregroundColor: AppColors.isDark(context) ? const Color(0xFF06281C) : Colors.white,
            ),
      body: Column(
        children: [
          TabHeader(
            title: widget.boss == 'history' ? 'ប្រវត្តិ' : (_isIn ? 'ឯកសារចូល' : 'ឯកសារចេញ'),
            subtitle: _total > 0 ? '$_total ឯកសារ' : null,
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    onChanged: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'ស្វែងរកលេខកូដ លេខឯកសារ ឬកម្មវត្ថុ',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchCtl.clear();
                                _onSearch('');
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                ),
                if (_isIn && !_isBoss) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'ស្ថានភាព',
                    onPressed: () async {
                      final r = await showSelectSheet(
                        context,
                        title: 'ស្ថានភាព',
                        selected: _status,
                        options: [
                          for (final e in transferStatus.entries) Option(e.key, e.value.label),
                        ],
                      );
                      if (r != null && r != _status) {
                        setState(() => _status = r);
                        _load(reset: true);
                      }
                    },
                    icon: Badge(
                      isLabelVisible: _status.isNotEmpty,
                      smallSize: 8,
                      child: const Icon(Icons.filter_list_rounded),
                    ),
                  ),
                ],
              ],
            ),
                if (!_isIn) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (value, label) in const [
                          ('', 'ទាំងអស់'),
                          ('new', 'ថ្មី'),
                          ('process', 'កំពុងដំណើរការ'),
                          ('close', 'បិទ'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _FilterChip(
                              label: label,
                              selected: _status == value,
                              onTap: () {
                                if (_status == value) return;
                                setState(() => _status = value);
                                _load(reset: true);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _body(rows),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<Json> rows) {
    if (_loading && _rows.isEmpty) return const LoadingList();
    if (_error.isNotEmpty && _rows.isEmpty) {
      return ListView(children: [ErrorState(_error, onRetry: () => _load(reset: true))]);
    }
    if (rows.isEmpty) {
      return ListView(
        children: [
          EmptyState(_search.isNotEmpty || _status.isNotEmpty
              ? 'រកមិនឃើញទិន្នន័យដែលត្រូវនឹងការស្វែងរក'
              : (widget.boss == 'inbox' ? 'មិនមានឯកសារត្រូវពិនិត្យទេ' : 'មិនទាន់មានឯកសារ')),
        ],
      );
    }
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20, 4, 20, _isIn ? 24 : 96),
      itemCount: rows.length + 1,
      separatorBuilder: (_, i) => i < rows.length - 1 ? const Divider(height: 1) : const SizedBox.shrink(),
      itemBuilder: (_, i) {
        if (i == rows.length) {
          if (_loading) {
            return const SkeletonFooter();
          }
          return const SizedBox.shrink();
        }
        return _isIn ? _inTile(rows[i]) : _outTile(rows[i]);
      },
    );
  }

  Widget _inTile(Json tr) {
    final d = asObj(tr['document_id']);
    final st = transferStatus[s(tr['status'])];
    // the Big Boss cares about WHO sent it
    final fromUser = _isBoss ? personName(asObj(tr['from_user_id'])) : '';
    final from = fromUser.isNotEmpty
        ? fromUser
        : s(asObj(tr['from_office_id'])['name']).isNotEmpty
            ? s(asObj(tr['from_office_id'])['name'])
            : s(asObj(d['office_id_open'])['name']);
    return _DocCard(
      code: s(d['code_of_document']),
      number: s(d['number_document']),
      type: s(asObj(d['document_type_id'])['name']),
      objective: s(d['objective']),
      line1: 'ពី: ${from.isEmpty ? '-' : from}',
      line2: 'ផ្ញើ: ${formatDate(tr['date_sent'])}',
      badge: st == null ? null : StatusBadge(st.label, tone: st.tone),
      highlight: s(tr['status']) == 'pending',
      onTap: () => _open(s(d['_id'])),
    );
  }

  Widget _outTile(Json d) {
    final st = docStatus[s(d['status'])];
    return _DocCard(
      code: s(d['code_of_document']),
      number: s(d['number_document']),
      type: s(asObj(d['document_type_id'])['name']),
      objective: s(d['objective']),
      line1: 'ទៅ: ${receiverText(d)}',
      line2: 'ចុះហត្ថលេខា: ${formatDate(d['date_sign'])}',
      badge: st == null ? null : StatusBadge(st.label, tone: st.tone),
      onTap: () => _open(s(d['_id'])),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final on = dark ? AppColors.darkAccent : AppColors.primaryDark;
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? on : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? on : AppColors.border(context)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? (dark ? const Color(0xFF06281C) : Colors.white) : null,
          ),
        ),
      ),
    );
  }
}

/// One document row: flat, separated by hairlines (design A).
class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.code,
    required this.number,
    required this.type,
    required this.objective,
    required this.line1,
    required this.line2,
    required this.onTap,
    this.badge,
    this.highlight = false,
  });

  final String code;
  final String number;
  final String type;
  final String objective;
  final String line1;
  final String line2;
  final Widget? badge;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final meta = [if (number.isNotEmpty) 'លេខ $number', if (type.isNotEmpty) type].join(' · ');
    return Material(
      color: highlight ? AppColors.warn.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      code.isEmpty ? '-' : code,
                      style: t.labelLarge?.copyWith(color: AppColors.strong(context), fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                  if (badge != null) badge!,
                ],
              ),
              const SizedBox(height: 2),
              Text(
                objective.isEmpty ? (number.isEmpty ? '-' : number) : objective,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 15.5, height: 1.5),
              ),
              if (meta.isNotEmpty)
                Text(meta, style: t.bodySmall?.copyWith(color: AppColors.muted, fontSize: 12.5)),
              Text('$line1 · $line2',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}
