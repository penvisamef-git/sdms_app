import 'package:flutter/material.dart';

import '../core/json.dart';
import '../core/theme.dart';

const _levelLabel = {
  'unit': 'អង្គភាព',
  'general_directorate': 'អគ្គនាយកដ្ឋាន',
  'department': 'នាយកដ្ឋាន',
  'office': 'ការិយាល័យ',
};

/// A node of the org tree plus the selectable office ids below it.
class OrgNode {
  OrgNode(this.id, this.name, this.level, this.children, this.leaves);

  final String id;
  final String name;
  final String level;
  final List<OrgNode> children;

  /// office ids selectable under this node (its own id for an office, never [excludeId])
  final List<String> leaves;
}

List<OrgNode> buildOrgTree(List<Json> raw, {String? excludeId}) {
  OrgNode build(Json n) {
    final kids = asList(n['children']).map(build).toList();
    final id = s(n['_id']);
    final isOffice = s(n['level']) == 'office' && id != excludeId;
    return OrgNode(
      id,
      s(n['name']),
      s(n['level']),
      kids,
      [if (isOffice) id, for (final k in kids) ...k.leaves],
    );
  }

  return raw.map(build).toList();
}

/// What was picked: the node and every office id below it.
class OrgPick {
  const OrgPick(this.id, this.name, this.offices);

  final String id;
  final String name;
  final List<String> offices;
}

/// Pick ONE unit / directorate / department / office. Higher levels mean every office below.
/// Returns null when closed, an [OrgPick] with empty id when cleared.
Future<OrgPick?> showOrgTreeSheet(
  BuildContext context, {
  required List<OrgNode> tree,
  String selectedId = '',
}) {
  return showModalBottomSheet<OrgPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _OrgSheet(tree: tree, selectedId: selectedId),
  );
}

class _OrgSheet extends StatefulWidget {
  const _OrgSheet({required this.tree, required this.selectedId});

  final List<OrgNode> tree;
  final String selectedId;

  @override
  State<_OrgSheet> createState() => _OrgSheetState();
}

class _OrgSheetState extends State<_OrgSheet> {
  final Set<String> _open = {};
  String _kw = '';

  bool _match(OrgNode n, String kw) => n.name.toLowerCase().contains(kw);

  /// Nodes to show as rows (flattened) with their depth.
  List<(OrgNode, int, bool)> _rows() {
    final out = <(OrgNode, int, bool)>[];
    final kw = _kw.toLowerCase();

    // returns true when this subtree has a match
    bool walk(OrgNode n, int depth, List<(OrgNode, int, bool)> into) {
      final sub = <(OrgNode, int, bool)>[];
      var any = false;
      for (final c in n.children) {
        if (walk(c, depth + 1, sub)) any = true;
      }
      final self = kw.isEmpty || _match(n, kw);
      if (!self && !any) return false;
      final expanded = kw.isNotEmpty ? any : _open.contains(n.id);
      into.add((n, depth, expanded));
      if (expanded) into.addAll(sub);
      return true;
    }

    for (final n in widget.tree) {
      walk(n, 0, out);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = _rows();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('អង្គភាពទទួល', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (widget.selectedId.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.pop(context, const OrgPick('', '', [])),
                      child: const Text('សម្អាត'),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'ការជ្រើសរើសអង្គភាព អគ្គនាយកដ្ឋាន ឬនាយកដ្ឋាន នឹងផ្ញើទៅគ្រប់ការិយាល័យខាងក្រោម។',
                style: t.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                decoration: const InputDecoration(hintText: 'ស្វែងរក...', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _kw = v.trim()),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('រកមិនឃើញ', style: TextStyle(color: AppColors.muted)))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final (n, depth, expanded) = rows[i];
                        final disabled = n.leaves.isEmpty;
                        final picked = n.id == widget.selectedId;
                        return InkWell(
                          onTap: disabled
                              ? null
                              : () => Navigator.pop(context, OrgPick(n.id, n.name, n.leaves)),
                          child: Padding(
                            padding: EdgeInsets.only(left: 8.0 + depth * 18, right: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
                                  child: n.children.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                                          onPressed: () => setState(() {
                                            if (!_open.remove(n.id)) _open.add(n.id);
                                          }),
                                        ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n.name,
                                          style: TextStyle(
                                            color: disabled ? AppColors.other : null,
                                            fontWeight: picked ? FontWeight.w800 : FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          [
                                            _levelLabel[n.level] ?? '',
                                            if (n.level != 'office' && n.leaves.isNotEmpty)
                                              '${n.leaves.length} ការិយាល័យ',
                                          ].where((e) => e.isNotEmpty).join(' · '),
                                          style: t.bodySmall?.copyWith(color: AppColors.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (picked) const Icon(Icons.check_circle, color: AppColors.primary),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
