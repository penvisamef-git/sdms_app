import 'package:flutter/material.dart';

import '../core/json.dart';
import '../core/theme.dart';
import 'common.dart';
import 'org_tree_picker.dart';
import 'select_sheet.dart';

/// "អ្នកទទួល": one receiving org node (all offices below it) and/or one receiving user.
class ReceiverCard extends StatelessWidget {
  const ReceiverCard({
    super.key,
    required this.tree,
    required this.users,
    required this.myOfficeId,
    required this.myUserId,
    required this.office,
    required this.userId,
    required this.onOfficeChanged,
    required this.onUserChanged,
    this.disabled = false,
    this.footer,
  });

  /// raw nodes of GET /master-data/unit-tree
  final List<Json> tree;
  final List<Json> users;
  final String myOfficeId;
  final String myUserId;
  final OrgPick? office;
  final String userId;
  final ValueChanged<OrgPick?> onOfficeChanged;
  final ValueChanged<String> onUserChanged;
  final bool disabled;
  final Widget? footer;

  bool _inOffices(Json u, List<String>? offices) =>
      offices == null || offices.isEmpty || offices.contains(idOf(u['office_id']));

  @override
  Widget build(BuildContext context) {
    final offices = office?.offices;
    final options = users
        .where((u) => s(u['_id']) != myUserId && u['status'] != false && u['is_super_admin'] != true)
        .where((u) => _inOffices(u, offices))
        .map((u) => Option(
              s(u['_id']),
              personName(u),
              sub: [s(asObj(u['office_id'])['name']), s(u['email'])].where((e) => e.isNotEmpty).join(' · '),
            ))
        .toList();

    return SectionCard(
      title: 'អ្នកទទួល',
      subtitle: 'ជ្រើសរើសអង្គភាពទទួល និង/ឬអ្នកប្រើប្រាស់ទទួលម្នាក់',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: disabled
                ? null
                : () async {
                    FocusScope.of(context).unfocus();
                    final r = await showOrgTreeSheet(
                      context,
                      tree: buildOrgTree(tree, excludeId: myOfficeId),
                      selectedId: office?.id ?? '',
                    );
                    if (r == null) return;
                    if (r.id.isEmpty) {
                      onOfficeChanged(null);
                      return;
                    }
                    onOfficeChanged(r);
                    // a chosen user outside the new offices is dropped
                    if (userId.isNotEmpty) {
                      final chosen = users.where((u) => s(u['_id']) == userId);
                      if (chosen.isNotEmpty && !_inOffices(chosen.first, r.offices)) onUserChanged('');
                    }
                  },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'អង្គភាពទទួល',
                suffixIcon: Icon(Icons.account_tree_outlined),
              ),
              isEmpty: office == null,
              child: Text(
                office == null ? '-- ជ្រើសរើសអង្គភាព --' : office!.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: office == null ? const TextStyle(color: AppColors.muted) : null,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelectField(
            label: 'អ្នកប្រើប្រាស់ទទួល',
            options: options,
            value: userId,
            enabled: !disabled,
            onChanged: onUserChanged,
            hint: '-- ជ្រើសរើសអ្នកប្រើប្រាស់ --',
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}
