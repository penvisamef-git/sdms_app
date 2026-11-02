import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'doc_helpers.dart';

String _place(dynamic office, dynamic user) {
  final parts = [s(asObj(office)['name']), personName(user)].where((e) => e.isNotEmpty).toList();
  return parts.isEmpty ? '-' : parts.join(' · ');
}

/// Summary + current holders + timeline of every hop. [data] = response.data of GET /document/:id/tracking.
class TrackingPanel extends StatelessWidget {
  const TrackingPanel({super.key, required this.data});

  final Json? data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (data == null) {
      return const Text('មិនមានទិន្នន័យតាមដាន', style: TextStyle(color: AppColors.muted));
    }
    final summary = asObj(data!['summary']);
    final timeline = asList(data!['timeline']);
    final holders = asList(summary['current_holders']);

    Widget tile(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: AppColors.strong(context))),
              Text(label, style: t.bodySmall?.copyWith(color: AppColors.muted, fontSize: 11.5)),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 16) / 3;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in [
                ('ជំហានសរុប', s(summary['total_steps'] ?? 0)),
                ('ការផ្ទេរសរុប', s(summary['total_transfers'] ?? 0)),
                ('អង្គភាពឆ្លងកាត់', s(summary['offices_passed'] ?? 0)),
                ('អ្នកពាក់ព័ន្ធ', s(summary['users_involved'] ?? 0)),
                ('រុញត្រឡប់', s(summary['returns'] ?? 0)),
                ('រយៈពេលសរុប', formatHours(summary['total_hours'])),
              ])
                SizedBox(width: w, child: tile(e.$1, e.$2)),
            ],
          );
        }),
        const SizedBox(height: 10),
        Text('ផ្ញើដំបូង: ${formatDateTime(summary['first_sent'])}', style: t.bodySmall?.copyWith(color: AppColors.muted)),
        Text('សកម្មភាពចុងក្រោយ: ${formatDateTime(summary['last_action'])}',
            style: t.bodySmall?.copyWith(color: AppColors.muted)),
        const SizedBox(height: 16),
        Text('កំពុងស្ថិតនៅ', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (holders.isEmpty)
          Text('មិនមានអ្នកកាន់ឯកសារនៅពេលនេះទេ (ដំណើរការបានបញ្ចប់ ឬមិនទាន់ផ្ញើ)',
              style: t.bodySmall?.copyWith(color: AppColors.muted))
        else
          for (final h in holders)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.softOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.isDark(context) ? AppColors.darkAccent : AppColors.primaryDark,
                    child: Text(
                      () {
                        final n = _place(h['office'], h['user']);
                        return n == '-' ? '?' : String.fromCharCodes(n.runes.take(1));
                      }(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.isDark(context) ? const Color(0xFF06281C) : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_place(h['office'], h['user']), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('តាំងពី ${formatDateTime(h['since'])}',
                            style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                  if (transferStatus[s(h['status'])] != null)
                    StatusBadge(transferStatus[s(h['status'])]!.label, tone: transferStatus[s(h['status'])]!.tone),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Text('ដំណើរការឯកសារ', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (timeline.isEmpty)
          Text('ឯកសារនេះមិនទាន់ត្រូវបានផ្ញើនៅឡើយទេ', style: t.bodySmall?.copyWith(color: AppColors.muted))
        else
          for (var i = 0; i < timeline.length; i++) _TimelineItem(item: timeline[i], last: i == timeline.length - 1),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.item, required this.last});

  final Json item;
  final bool last;

  IconData get _icon {
    switch (s(item['action'])) {
      case 'forward':
        return Icons.share_outlined;
      case 'return':
        return Icons.undo_rounded;
      default:
        return Icons.send_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = transferStatus[s(item['status'])];
    final isReturn = s(item['action']) == 'return';
    final now = s(item['status']) == 'pending' || s(item['status']) == 'received';
    final dark = AppColors.isDark(context);
    final Color dot = now ? AppColors.card(context) : (isReturn ? AppColors.danger : AppColors.primary);
    final Color ring = now ? AppColors.gold : (isReturn ? AppColors.dangerSoft : (dark ? const Color(0xFF1B3A2C) : const Color(0xFFDDEFE3)));
    final Color line = now ? AppColors.border(context) : (isReturn ? AppColors.danger : AppColors.primary);
    final flow = s(asObj(item['status_of_process_id'])['name']);
    final received = s(item['date_received']);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: ring, width: 3)),
                ),
                if (!last) Expanded(child: Container(width: 2, color: line)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: 12, bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('ជំហាន ${s(item['step'])}', style: t.bodySmall?.copyWith(color: AppColors.muted)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_icon, size: 15, color: isReturn ? AppColors.danger : AppColors.muted),
                          const SizedBox(width: 4),
                          Text(transferAction[s(item['action'])] ?? s(item['action']),
                              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      if (st != null) StatusBadge(st.label, tone: st.tone),
                      if (flow.isNotEmpty) StatusBadge(flow, tone: Tone.neutral),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${_place(item['from_office_id'], item['from_user_id'])}\n→ ${_place(item['to_office_id'], item['to_user_id'])}'),
                  const SizedBox(height: 4),
                  Text('ផ្ញើ: ${formatDateTime(item['date_sent'])}', style: t.bodySmall?.copyWith(color: AppColors.muted)),
                  if (received.isNotEmpty)
                    Text(
                      'ទទួល: ${formatDateTime(item['date_received'])}'
                      '${item['received_by'] != null ? ' (${personName(item['received_by'])})' : ''}',
                      style: t.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  if (s(item['date_done']).isNotEmpty)
                    Text('បញ្ចប់: ${formatDateTime(item['date_done'])}',
                        style: t.bodySmall?.copyWith(color: AppColors.muted)),
                  Text(
                    'រង់ចាំទទួល: ${formatHours(item['waiting_hours'])} · ស្ថិតនៅ: ${formatHours(item['holding_hours'])}',
                    style: t.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  if (s(item['note']).isNotEmpty) _note('ការណែនាំ: ${s(item['note'])}', context),
                  if (s(item['done_note']).isNotEmpty) _note('កំណត់ចំណាំបញ្ចប់: ${s(item['done_note'])}', context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _note(String text, BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(10),
        width: double.infinity,
        decoration: BoxDecoration(color: AppColors.softOf(context), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}
