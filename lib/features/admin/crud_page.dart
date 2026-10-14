import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/json.dart';
import '../../core/theme.dart';
import '../../data/services.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/select_sheet.dart';

enum FieldType { text, email, tel, password, textarea, select, checkbox }

/// One input of the add / edit form.
class FieldDef {
  const FieldDef(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.createOnly = false,
    this.hint,
    this.options,
    this.checkboxLabel,
  });

  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final bool createOnly; // e.g. password: set on create, changed through its own action
  final String? hint;

  /// Loads the choices of a select (parent records, roles ...).
  final Future<List<Option>> Function(Api api)? options;
  final String? checkboxLabel;
}

typedef RowText = String Function(Json row);

/// Generic list + add / edit / delete page for one CRUD resource (same as the web MasterDataPage).
class CrudPage extends ConsumerStatefulWidget {
  const CrudPage({
    super.key,
    required this.title,
    required this.resource,
    required this.fields,
    required this.searchKeys,
    required this.rowTitle,
    this.rowSubtitle,
    this.canDelete,
    this.rowActions,
    this.appBarActions = const [],
  });

  final String title;
  final Resource Function(Api api) resource;
  final List<FieldDef> fields;
  final List<String> searchKeys;
  final RowText rowTitle;
  final RowText? rowSubtitle;
  final bool Function(Json row, Json? me)? canDelete;

  /// Extra buttons in each row's menu: label, icon, action.
  final List<RowAction> Function(Json row)? rowActions;

  /// Extra icon buttons in the top bar.
  final List<Widget> appBarActions;

  @override
  ConsumerState<CrudPage> createState() => _CrudPageState();
}

class RowAction {
  const RowAction(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context, WidgetRef ref) onTap;
}

class _CrudPageState extends ConsumerState<CrudPage> {
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

  Resource get _res => widget.resource(ref.read(apiProvider));

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _more();
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
    if (reset) _page = 1;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await _res.list({
        'page': _page,
        'limit': 20,
        if (_search.isNotEmpty) 'q': _search,
        if (_search.isNotEmpty) 'q_key': widget.searchKeys,
      });
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

  void _more() {
    if (_loading || _page >= _totalPages) return;
    _page++;
    _load();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (v.trim() == _search) return;
      _search = v.trim();
      _load(reset: true);
    });
  }

  Future<void> _openForm([Json? row]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _FormSheet(
        title: row == null ? 'បន្ថែម${widget.title}' : 'កែប្រែ${widget.title}',
        fields: widget.fields,
        resource: _res,
        row: row,
      ),
    );
    if (saved == true && mounted) {
      showSnack(context, 'បានរក្សាទុក!');
      _load(reset: true);
    }
  }

  Future<void> _delete(Json row) async {
    final ok = await confirmDialog(
      context,
      title: 'លុប "${widget.rowTitle(row)}"?',
      message: 'សកម្មភាពនេះមិនអាចត្រឡប់វិញបានទេ។',
      confirmText: 'លុប',
      danger: true,
    );
    if (!ok) return;
    try {
      final res = await _res.remove(s(row['_id']));
      if (!mounted) return;
      showSnack(context, s(res['message']).isNotEmpty ? s(res['message']) : 'បានលុប!');
      _load(reset: true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).user;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          ...widget.appBarActions,
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('$_total', style: t.titleSmall?.copyWith(color: AppColors.muted))),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('បន្ថែម'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _searchCtl,
              onChanged: (v) {
                setState(() {});
                _onSearch(v);
              },
              decoration: InputDecoration(
                hintText: 'ស្វែងរក...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchCtl.clear();
                          setState(() {});
                          _onSearch('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.read(apiClientProvider).clearCache();
                await _load(reset: true);
              },
              child: _body(me),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(Json? me) {
    if (_loading && _rows.isEmpty) return const LoadingList();
    if (_error.isNotEmpty && _rows.isEmpty) {
      return ListView(children: [ErrorState(_error, onRetry: () => _load(reset: true))]);
    }
    if (_rows.isEmpty) {
      return ListView(children: [EmptyState(_search.isEmpty ? 'មិនទាន់មានទិន្នន័យ' : 'រកមិនឃើញទិន្នន័យដែលត្រូវនឹងការស្វែងរក')]);
    }
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: _rows.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == _rows.length) {
          return _loading
              ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)))
              : const SizedBox.shrink();
        }
        final row = _rows[i];
        final inactive = row['status'] == false;
        final sub = widget.rowSubtitle?.call(row) ?? '';
        final extras = widget.rowActions?.call(row) ?? const <RowAction>[];
        final deletable = widget.canDelete?.call(row, me) ?? true;
        return Card(
          child: ListTile(
            onTap: () => _openForm(row),
            title: Text(widget.rowTitle(row).isEmpty ? '-' : widget.rowTitle(row),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (inactive) const StatusBadge('អសកម្ម', tone: Tone.danger),
                PopupMenuButton<int>(
                  onSelected: (v) {
                    if (v == -1) {
                      _openForm(row);
                    } else if (v == -2) {
                      _delete(row);
                    } else {
                      extras[v].onTap(context, ref);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: -1, child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('កែប្រែ'))),
                    for (var k = 0; k < extras.length; k++)
                      PopupMenuItem(value: k, child: ListTile(leading: Icon(extras[k].icon), title: Text(extras[k].label))),
                    if (deletable)
                      const PopupMenuItem(
                        value: -2,
                        child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('លុប')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FormSheet extends ConsumerStatefulWidget {
  const _FormSheet({required this.title, required this.fields, required this.resource, this.row});

  final String title;
  final List<FieldDef> fields;
  final Resource resource;
  final Json? row;

  @override
  ConsumerState<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends ConsumerState<_FormSheet> {
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, dynamic> _values = {};
  final Map<String, List<Option>> _options = {};
  bool _status = true;
  bool _saving = false;
  String _error = '';

  bool get _editing => widget.row != null;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final raw = widget.row?[f.key];
      if (f.type == FieldType.checkbox) {
        _values[f.key] = raw == true;
      } else if (f.type == FieldType.select) {
        _values[f.key] = raw is Map ? s(raw['_id']) : s(raw);
        f.options?.call(ref.read(apiProvider)).then((o) {
          if (mounted) setState(() => _options[f.key] = o);
        }).catchError((_) {});
      } else {
        _ctl[f.key] = TextEditingController(text: s(raw));
      }
    }
    _status = widget.row?['status'] != false;
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = '');
    final active = widget.fields.where((f) => !(_editing && f.createOnly)).toList();
    for (final f in active) {
      if (!f.required || f.type == FieldType.checkbox) continue;
      final v = f.type == FieldType.select ? s(_values[f.key]) : _ctl[f.key]!.text;
      if (v.trim().isEmpty) {
        setState(() => _error = 'សូមបញ្ចូល ${f.label}');
        return;
      }
    }

    final payload = <String, dynamic>{'status': _status};
    for (final f in active) {
      switch (f.type) {
        case FieldType.checkbox:
          payload[f.key] = _values[f.key] == true;
        case FieldType.select:
          payload[f.key] = s(_values[f.key]).isEmpty ? null : _values[f.key];
        case FieldType.password:
          payload[f.key] = _ctl[f.key]!.text; // never trimmed
        default:
          payload[f.key] = _ctl[f.key]!.text.trim();
      }
    }

    setState(() => _saving = true);
    try {
      if (_editing) {
        await widget.resource.update(s(widget.row!['_id']), payload);
      } else {
        await widget.resource.create(payload);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = widget.fields.where((f) => !(_editing && f.createOnly)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  IconButton(onPressed: _saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                children: [
                  for (final f in active) ...[
                    _field(f),
                    const SizedBox(height: 14),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ស្ថានភាព'),
                    subtitle: Text(_status ? 'សកម្ម' : 'អសកម្ម'),
                    value: _status,
                    onChanged: _saving ? null : (v) => setState(() => _status = v),
                  ),
                  if (_error.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error, style: const TextStyle(color: AppColors.danger)),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text('បោះបង់'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('រក្សាទុក'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(FieldDef f) {
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.type) {
      case FieldType.select:
        final opts = (_options[f.key] ?? const <Option>[])
            .where((o) => !_editing || o.value != s(widget.row!['_id']))
            .toList();
        return SelectField(
          label: label,
          options: opts,
          value: s(_values[f.key]),
          enabled: !_saving,
          hint: f.hint ?? '-- ជ្រើសរើស --',
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.checkbox:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: f.checkboxLabel == null ? null : Text(f.checkboxLabel!),
          value: _values[f.key] == true,
          onChanged: _saving ? null : (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.textarea:
        return TextField(
          controller: _ctl[f.key],
          enabled: !_saving,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: label, hintText: f.hint, alignLabelWithHint: true),
        );
      default:
        return TextField(
          controller: _ctl[f.key],
          enabled: !_saving,
          obscureText: f.type == FieldType.password,
          keyboardType: f.type == FieldType.email
              ? TextInputType.emailAddress
              : f.type == FieldType.tel
                  ? TextInputType.phone
                  : TextInputType.text,
          autocorrect: false,
          decoration: InputDecoration(labelText: label, hintText: f.hint),
        );
    }
  }
}
