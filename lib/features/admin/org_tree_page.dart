import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// Organisation structure (same as the web "រចនាសម្ព័ន្ធ" tab):
/// Unit → General directorate → Department → Office → Users.
class OrgTreePage extends ConsumerStatefulWidget {
  const OrgTreePage({super.key, required this.masterKey, required this.title});

  /// unit | general-directorate | department | office
  final String masterKey;
  final String title;

  @override
  ConsumerState<OrgTreePage> createState() => _OrgTreePageState();
}

class _Node {
  _Node(this.data, this.level);

  final Json data;
  final String level; // unit | general_directorate | department | office
  final List<_Node> children = [];
  final List<Json> users = [];
  int userCount = 0;

  String get id => s(data['_id']);
  String get name => s(data['name']);
  String get sub => s(data['name_in_eng']);
  bool get inactive => data['status'] == false;
}

const _levelLabel = {
  'unit': 'អង្គភាព',
  'general_directorate': 'អគ្គនាយកដ្ឋាន',
  'department': 'នាយកដ្ឋាន',
  'office': 'ការិយាល័យ',
};

const _levelIcon = {
  'unit': Icons.account_balance_outlined,
  'general_directorate': Icons.business_outlined,
  'department': Icons.domain_outlined,
  'office': Icons.meeting_room_outlined,
};

class _Row {
  const _Row(this.depth, {this.node, this.user});

  final int depth;
  final _Node? node;
  final Json? user;
}

class _OrgTreePageState extends ConsumerState<OrgTreePage> {
  final _search = TextEditingController();
  List<_Node> _roots = [];
  final Set<String> _open = {};
  bool _loading = true;
  String _error = '';
  String _kw = '';
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // The API sends users as children with level "user": split them off and count them
  _Node _build(Json raw) {
    final node = _Node(raw, s(raw['level']).isEmpty ? 'unit' : s(raw['level']));
    for (final k in asList(raw['children'])) {
      if (s(k['level']) == 'user') {
        node.users.add(k);
      } else {
        node.children.add(_build(k));
      }
    }
    node.userCount = node.users.length + node.children.fold<int>(0, (a, c) => a + c.userCount);
    return node;
  }

  Future<List<Json>> _fetch() async {
    final api = ref.read(apiProvider);
    if (widget.masterKey == 'office') {
      // there is no office-tree route: build it from the office and user lists
      final res = await Future.wait([api.offices.all(), api.users.all().catchError((_) => <String, dynamic>{})]);
      final byOffice = <String, List<Json>>{};
      for (final u in asList(res[1]['data'])) {
        if (u['is_super_admin'] == true) continue;
        final o = u['office_id'];
        final oid = o is Map ? s(o['_id']) : s(o);
        if (oid.isEmpty) continue;
        (byOffice[oid] ??= []).add({...u, 'level': 'user'});
      }
      return [
        for (final o in asList(res[0]['data']))
          {...o, 'level': 'office', 'children': byOffice[s(o['_id'])] ?? <Json>[]},
      ];
    }
    final res = await api.orgTree(widget.masterKey);
    return asList(res['data']);
  }

  Future<void> _load() async {
    if (_roots.isEmpty && widget.masterKey != 'office') {
      final saved = ref.read(apiProvider).peekOrgTree(widget.masterKey);
      if (saved != null) {
        _roots = asList(saved['data']).map(_build).toList();
        if (_roots.isNotEmpty && _firstLoad) {
          _firstLoad = false;
          _open.addAll(_roots.map((r) => r.id));
        }
      }
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final roots = (await _fetch()).map(_build).toList();
      if (!mounted) return;
      setState(() {
        _roots = roots;
        if (_firstLoad) {
          _firstLoad = false;
          _open.addAll(roots.map((r) => r.id));
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hit(List<String> parts) => parts.where((e) => e.isNotEmpty).join(' ').toLowerCase().contains(_kw);

  bool _userHit(Json u) =>
      _hit([s(u['firstname']), s(u['lastname']), s(u['email']), s(u['contact']), s(u['job_title'])]);

  /// Keep only what matches the search (a matching node keeps its whole subtree).
  _Node? _filter(_Node n) {
    if (_kw.isEmpty || _hit([n.name, n.sub])) return n;
    final kids = [for (final c in n.children) _filter(c)].whereType<_Node>().toList();
    final users = n.users.where(_userHit).toList();
    if (kids.isEmpty && users.isEmpty) return null;
    final copy = _Node(n.data, n.level)
      ..children.addAll(kids)
      ..users.addAll(users)
      ..userCount = n.userCount;
    return copy;
  }

  void _flatten(_Node n, int depth, List<_Row> out) {
    out.add(_Row(depth, node: n));
    final hasKids = n.children.isNotEmpty || n.users.isNotEmpty;
    if (!hasKids || !(_kw.isNotEmpty || _open.contains(n.id))) return;
    for (final c in n.children) {
      _flatten(c, depth + 1, out);
    }
    for (final u in n.users) {
      out.add(_Row(depth + 1, user: u));
    }
  }

  void _collectOpenable(List<_Node> nodes, Set<String> ids) {
    for (final n in nodes) {
      if (n.children.isNotEmpty || n.users.isNotEmpty) ids.add(n.id);
      _collectOpenable(n.children, ids);
    }
  }

  void _showUser(Json u) {
    final rows = <MapEntry<String, String>>[
      MapEntry('អ៊ីមែល', s(u['email'])),
      MapEntry('លេខទំនាក់ទំនង', s(u['contact'])),
      MapEntry('មុខតំណែង', s(u['job_title'])),
      MapEntry('ស្ថាប័ន/អង្គភាព', s(u['organization'])),
      MapEntry('ក្រុមសិទ្ធិ', u['role'] is String ? s(u['role']) : s(asObj(u['role'])['name'])),
      MapEntry('ស្ថានភាព', u['status'] == false ? 'អសកម្ម' : 'សកម្ម'),
    ].where((e) => e.value.isNotEmpty).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(personName(u), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              for (final r in rows) InfoRow(r.key, r.value),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = [for (final r in _roots) _filter(r)].whereType<_Node>().toList();
    final rows = <_Row>[];
    for (final r in visible) {
      _flatten(r, 0, rows);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('រចនាសម្ព័ន្ធ · ${widget.title}'),
        actions: [
          IconButton(
            tooltip: 'ពង្រីកទាំងអស់',
            icon: const Icon(Icons.unfold_more_rounded),
            onPressed: () => setState(() => _collectOpenable(_roots, _open)),
          ),
          IconButton(
            tooltip: 'បង្រួមទាំងអស់',
            icon: const Icon(Icons.unfold_less_rounded),
            onPressed: () => setState(_open.clear),
          ),
          IconButton(tooltip: 'ផ្ទុកឡើងវិញ', icon: const Icon(Icons.refresh_rounded), onPressed: _loading ? null : _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _kw = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'ស្វែងរកអង្គភាព នាយកដ្ឋាន ការិយាល័យ ឬអ្នកប្រើប្រាស់...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _kw.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _kw = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: _loading && _roots.isEmpty
                ? const SkeletonList(compact: true)
                : _error.isNotEmpty
                    ? ErrorState(_error, onRetry: _load)
                    : rows.isEmpty
                        ? EmptyState(_kw.isEmpty ? 'មិនទាន់មានទិន្នន័យ' : 'រកមិនឃើញទិន្នន័យដែលត្រូវនឹងការស្វែងរក')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 24),
                              itemCount: rows.length,
                              itemBuilder: (_, i) => _buildRow(rows[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_Row r) {
    final t = Theme.of(context).textTheme;
    final left = 12.0 + r.depth * 20;

    if (r.user != null) {
      final u = r.user!;
      return InkWell(
        onTap: () => _showUser(u),
        child: Padding(
          padding: EdgeInsets.fromLTRB(left + 28, 8, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(personName(u), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      [s(u['job_title']), s(u['email'])].where((e) => e.isNotEmpty).join(' · '),
                      style: t.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (u['status'] == false) const StatusBadge('អសកម្ម'),
            ],
          ),
        ),
      );
    }

    final n = r.node!;
    final hasKids = n.children.isNotEmpty || n.users.isNotEmpty;
    final open = _kw.isNotEmpty || _open.contains(n.id);
    return InkWell(
      onTap: hasKids
          ? () => setState(() {
                if (!_open.remove(n.id)) _open.add(n.id);
              })
          : null,
      child: Padding(
        padding: EdgeInsets.fromLTRB(left, 10, 16, 10),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: hasKids ? Icon(open ? Icons.expand_more : Icons.chevron_right, size: 22) : null,
            ),
            Icon(_levelIcon[n.level] ?? Icons.folder_outlined, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    [if (n.sub.isNotEmpty) n.sub, _levelLabel[n.level] ?? ''].where((e) => e.isNotEmpty).join(' · '),
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (n.inactive) ...[const StatusBadge('អសកម្ម'), const SizedBox(width: 6)],
            if (n.userCount > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_rounded, size: 14, color: AppColors.muted),
                  const SizedBox(width: 2),
                  Text('${n.userCount}', style: t.labelMedium?.copyWith(color: AppColors.muted)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
