import 'package:flutter/material.dart';

import '../core/json.dart';
import '../core/theme.dart';
import 'common.dart';
import 'cover_slip.dart';
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
    this.cover,
    this.defaultSubject = '',
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

  /// cover slip fields; shown when the chosen user is the Big Boss
  final CoverControllers? cover;
  final String defaultSubject;

  bool _inOffices(Json u, List<String>? offices) =>
      offices == null || offices.isEmpty || offices.contains(idOf(u['office_id']));

  Future<void> _pickOffice(BuildContext context) async {
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
  }

  Future<void> _pickUser(BuildContext context, List<Option> options) async {
    FocusScope.of(context).unfocus();
    final r = await showSelectSheet(context, title: 'អ្នកប្រើប្រាស់ទទួល', options: options, selected: userId);
    if (r != null) onUserChanged(r);
  }

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

    final dark = AppColors.isDark(context);
    String userName = '';
    if (userId.isNotEmpty) {
      final found = users.where((u) => s(u['_id']) == userId);
      userName = found.isEmpty ? 'អ្នកប្រើប្រាស់' : personName(found.first);
    }

    final toBoss = cover != null && isBossUser(users, userId);
    String fromOffice = '';
    final me = users.where((u) => s(u['_id']) == myUserId);
    if (me.isNotEmpty) fromOffice = s(asObj(me.first['office_id'])['name']);

    return SectionCard(
      title: 'អ្នកទទួល',
      subtitle: 'ជ្រើសរើសអង្គភាពទទួល និង/ឬអ្នកប្រើប្រាស់ទទួលម្នាក់',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (office != null)
                _ReceiverChip(
                  label: office!.name,
                  background: AppColors.softOf(context),
                  foreground: AppColors.strong(context),
                  onRemove: disabled ? null : () => onOfficeChanged(null),
                ),
              if (userId.isNotEmpty)
                _ReceiverChip(
                  label: userName,
                  background: dark ? const Color(0xFF3A2F0F) : const Color(0xFFFBF3D5),
                  foreground: dark ? const Color(0xFFE8D48A) : const Color(0xFF6B520A),
                  onRemove: disabled ? null : () => onUserChanged(''),
                ),
              if (office == null)
                _AddChip(label: 'អង្គភាព', onTap: disabled ? null : () => _pickOffice(context)),
              if (userId.isEmpty)
                _AddChip(label: 'អ្នកប្រើប្រាស់', onTap: disabled ? null : () => _pickUser(context, options)),
            ],
          ),
          if (toBoss) ...[
            const SizedBox(height: 14),
            CoverSlipForm(
              cover: cover!,
              fromOffice: fromOffice,
              toName: userName,
              defaultSubject: defaultSubject,
              disabled: disabled,
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

class _ReceiverChip extends StatelessWidget {
  const _ReceiverChip({required this.label, required this.background, required this.foreground, this.onRemove});

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34, maxWidth: 300),
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(17)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          InkResponse(
            radius: 16,
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.close_rounded, size: 16, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.isDark(context) ? AppColors.darkAccent : AppColors.primaryDark;
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: c.withValues(alpha: onTap == null ? 0.25 : 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 16, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
