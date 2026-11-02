import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/tab_header.dart';

class _Entry {
  const _Entry(this.title, this.subtitle, this.icon, this.path);

  final String title;
  final String subtitle;
  final IconData icon;
  final String path;
}

const _entries = [
  _Entry('អ្នកប្រើប្រាស់', 'គណនី តួនាទី និងពាក្យសម្ងាត់', Icons.people_alt_outlined, '/admin/users'),
  _Entry('អង្គភាព', 'Unit', Icons.account_balance_outlined, '/admin/master/unit'),
  _Entry('អគ្គនាយកដ្ឋាន', 'General directorate', Icons.business_outlined, '/admin/master/general-directorate'),
  _Entry('នាយកដ្ឋាន', 'Department', Icons.domain_outlined, '/admin/master/department'),
  _Entry('ការិយាល័យ', 'Office', Icons.meeting_room_outlined, '/admin/master/office'),
  _Entry('ប្រភេទឯកសារ', 'Document type', Icons.category_outlined, '/admin/master/document-type'),
  _Entry('ក្របខណ្ឌ', 'Framework', Icons.account_tree_outlined, '/admin/master/framework'),
  _Entry('ស្ថានភាពដំណើរការ', 'Status of process', Icons.timeline_outlined, '/admin/master/status-of-process'),
];

/// Super admin: users and master data.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TabHeader(title: 'គ្រប់គ្រង', subtitle: 'អ្នកប្រើប្រាស់ និងទិន្នន័យមេ'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
        for (final e in _entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: CircleAvatar(
                  backgroundColor: AppColors.softOf(context),
                  child: Icon(e.icon, color: AppColors.primary),
                ),
                title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(e.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(e.path),
              ),
            ),
          ),
            ],
          ),
        ),
      ],
    );
  }
}
