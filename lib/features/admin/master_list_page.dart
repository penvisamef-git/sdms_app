import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/json.dart';
import '../../data/services.dart';
import '../../widgets/common.dart';
import '../../widgets/select_sheet.dart';
import 'crud_page.dart';

String _name(Json r) => s(r['name']);

Future<List<Option>> _opts(Future<Json> Function() load, String Function(Json) label) async {
  final res = await load();
  return [for (final r in asList(res['data'])) Option(s(r['_id']), label(r))];
}

/// Name + the parent shown in brackets, e.g. "Office (Department)".
String _withParent(Json r, String parentKey) {
  final p = s(asObj(r[parentKey])['name']);
  return p.isEmpty ? _name(r) : '${_name(r)} ($p)';
}

class _Cfg {
  const _Cfg({
    required this.title,
    required this.resource,
    required this.fields,
    required this.searchKeys,
    required this.rowTitle,
    this.rowSubtitle,
  });

  final String title;
  final Resource Function(Api) resource;
  final List<FieldDef> fields;
  final List<String> searchKeys;
  final RowText rowTitle;
  final RowText? rowSubtitle;
}

const _nameKh = FieldDef('name', 'ឈ្មោះ (ខ្មែរ)', required: true);
const _nameEn = FieldDef('name_in_eng', 'ឈ្មោះ (អង់គ្លេស)');
const _note = FieldDef('note', 'កំណត់សម្គាល់', type: FieldType.textarea);

String _eng(Json r) => s(r['name_in_eng']);

final Map<String, _Cfg> _configs = {
  'unit': _Cfg(
    title: 'អង្គភាព',
    resource: (a) => a.units,
    fields: const [_nameKh, _nameEn, FieldDef('location', 'ទីតាំង'), _note],
    searchKeys: const ['name', 'name_in_eng', 'location'],
    rowTitle: _name,
    rowSubtitle: (r) => [_eng(r), s(r['location'])].where((e) => e.isNotEmpty).join(' · '),
  ),
  'general-directorate': _Cfg(
    title: 'អគ្គនាយកដ្ឋាន',
    resource: (a) => a.generalDirectorates,
    fields: [
      _nameKh,
      _nameEn,
      FieldDef('unit_id', 'អង្គភាព',
          type: FieldType.select,
          required: true,
          hint: '-- ជ្រើសរើសអង្គភាព --',
          options: (a) => _opts(a.units.all, _name)),
      _note,
    ],
    searchKeys: const ['name', 'name_in_eng'],
    rowTitle: _name,
    rowSubtitle: (r) => s(asObj(r['unit_id'])['name']),
  ),
  'department': _Cfg(
    title: 'នាយកដ្ឋាន',
    resource: (a) => a.departments,
    fields: [
      _nameKh,
      _nameEn,
      FieldDef('general_directorate_id', 'អគ្គនាយកដ្ឋាន',
          type: FieldType.select,
          required: true,
          hint: '-- ជ្រើសរើសអគ្គនាយកដ្ឋាន --',
          options: (a) => _opts(a.generalDirectorates.all, (r) => _withParent(r, 'unit_id'))),
      _note,
    ],
    searchKeys: const ['name', 'name_in_eng'],
    rowTitle: _name,
    rowSubtitle: (r) {
      final gd = asObj(r['general_directorate_id']);
      return [s(gd['name']), s(asObj(gd['unit_id'])['name'])].where((e) => e.isNotEmpty).join(' · ');
    },
  ),
  'office': _Cfg(
    title: 'ការិយាល័យ',
    resource: (a) => a.offices,
    fields: [
      _nameKh,
      _nameEn,
      FieldDef('department_id', 'នាយកដ្ឋាន',
          type: FieldType.select,
          required: true,
          hint: '-- ជ្រើសរើសនាយកដ្ឋាន --',
          options: (a) => _opts(a.departments.all, (r) => _withParent(r, 'general_directorate_id'))),
      _note,
    ],
    searchKeys: const ['name', 'name_in_eng'],
    rowTitle: _name,
    rowSubtitle: (r) {
      final d = asObj(r['department_id']);
      return [s(d['name']), s(asObj(d['general_directorate_id'])['name'])].where((e) => e.isNotEmpty).join(' · ');
    },
  ),
  'document-type': _Cfg(
    title: 'ប្រភេទឯកសារ',
    resource: (a) => a.documentTypes,
    fields: const [
      FieldDef('name', 'ឈ្មោះ', required: true),
      FieldDef('code', 'កូដ'),
      _note,
    ],
    searchKeys: const ['name', 'code'],
    rowTitle: _name,
    rowSubtitle: (r) => s(r['code']),
  ),
  'framework': _Cfg(
    title: 'ក្របខណ្ឌ',
    resource: (a) => a.frameworks,
    fields: [
      const FieldDef('name', 'ឈ្មោះ', required: true),
      const FieldDef('code', 'កូដ'),
      FieldDef('framework_parent_id', 'ក្របខណ្ឌមេ',
          type: FieldType.select,
          hint: '-- គ្មាន (ក្របខណ្ឌកំពូល) --',
          options: (a) => _opts(a.frameworks.all, (r) => s(r['code']).isEmpty ? _name(r) : '${s(r['code'])} - ${_name(r)}')),
      _note,
    ],
    searchKeys: const ['name', 'code'],
    rowTitle: _name,
    rowSubtitle: (r) => [s(r['code']), s(asObj(r['framework_parent_id'])['name'])].where((e) => e.isNotEmpty).join(' · '),
  ),
  'status-of-process': _Cfg(
    title: 'ស្ថានភាពដំណើរការ',
    resource: (a) => a.statusOfProcess,
    fields: const [FieldDef('name', 'ឈ្មោះ', required: true), _note],
    searchKeys: const ['name'],
    rowTitle: _name,
    rowSubtitle: (r) => s(r['note']),
  ),
};

const _treeKeys = {'unit', 'general-directorate', 'department', 'office'};

/// One master-data list, picked by [masterKey] (see /admin/master/:key in the router).
class MasterListPage extends StatelessWidget {
  const MasterListPage({super.key, required this.masterKey});

  final String masterKey;

  @override
  Widget build(BuildContext context) {
    final c = _configs[masterKey];
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState('រកមិនឃើញទំព័រនេះ'));
    }
    return CrudPage(
      key: ValueKey(masterKey),
      title: c.title,
      resource: c.resource,
      fields: c.fields,
      searchKeys: c.searchKeys,
      rowTitle: c.rowTitle,
      rowSubtitle: c.rowSubtitle,
      appBarActions: [
        // organisation lists also have the structure tree (same as the web "រចនាសម្ព័ន្ធ" tab)
        if (_treeKeys.contains(masterKey))
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'រចនាសម្ព័ន្ធ',
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () => ctx.push('/admin/tree/$masterKey', extra: c.title),
            ),
          ),
      ],
    );
  }
}
