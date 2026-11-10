import 'package:flutter/material.dart';

import '../core/json.dart';
import '../core/permission.dart';
import '../core/theme.dart';

/// The cover slip ("ក្រដាសសង្ខេប") sent with a document to the Big Boss: subject, summary and the sender's opinion.
class CoverControllers {
  final subject = TextEditingController();
  final content = TextEditingController();
  final opinion = TextEditingController();

  void clear() {
    subject.clear();
    content.clear();
    opinion.clear();
  }

  /// Request fields (only the filled ones, and only when the receiver is the Big Boss).
  Map<String, dynamic> body(bool toBoss) {
    if (!toBoss) return {};
    return {
      if (subject.text.trim().isNotEmpty) 'cover_subject': subject.text.trim(),
      if (content.text.trim().isNotEmpty) 'cover_content': content.text.trim(),
      if (opinion.text.trim().isNotEmpty) 'cover_opinion': opinion.text.trim(),
    };
  }

  void dispose() {
    subject.dispose();
    content.dispose();
    opinion.dispose();
  }
}

bool isBossUser(List<Json> users, String id) =>
    id.isNotEmpty && users.any((u) => s(u['_id']) == id && s(u['role']) == Role.boss);

Widget _route(BuildContext context, String from, String to) {
  final c = AppColors.strong(context);
  return Row(
    children: [
      Flexible(child: Text(from, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.muted),
      ),
      Flexible(child: Text(to, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13))),
    ],
  );
}

/// Form part: shown while the chosen receiver is the Big Boss. The subject is prefilled from the document.
class CoverSlipForm extends StatefulWidget {
  const CoverSlipForm({
    super.key,
    required this.cover,
    required this.fromOffice,
    required this.toName,
    this.defaultSubject = '',
    this.disabled = false,
  });

  final CoverControllers cover;
  final String fromOffice;
  final String toName;
  final String defaultSubject;
  final bool disabled;

  @override
  State<CoverSlipForm> createState() => _CoverSlipFormState();
}

class _CoverSlipFormState extends State<CoverSlipForm> {
  @override
  void initState() {
    super.initState();
    if (widget.cover.subject.text.trim().isEmpty && widget.defaultSubject.trim().isNotEmpty) {
      widget.cover.subject.text = widget.defaultSubject.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ក្រដាសសង្ខេបជូនថ្នាក់ដឹកនាំ', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _route(context, widget.fromOffice.isEmpty ? 'អង្គភាពរបស់អ្នក' : widget.fromOffice,
              widget.toName.isEmpty ? 'ថ្នាក់ដឹកនាំ' : widget.toName),
          const SizedBox(height: 12),
          TextField(
            controller: widget.cover.subject,
            enabled: !widget.disabled,
            decoration: const InputDecoration(labelText: 'កម្មវត្ថុ'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.cover.content,
            enabled: !widget.disabled,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'ខ្លឹមសារ (សង្ខេប)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.cover.opinion,
            enabled: !widget.disabled,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'យោបល់', alignLabelWithHint: true),
          ),
        ],
      ),
    );
  }
}

/// Read-only part: [transfer] = one timeline row (cover_* fields, from_office_id, to_user_id).
class CoverSlipView extends StatelessWidget {
  const CoverSlipView({super.key, required this.transfer});

  final Json? transfer;

  @override
  Widget build(BuildContext context) {
    final tr = transfer;
    if (tr == null) return const SizedBox.shrink();
    final subject = s(tr['cover_subject']);
    final content = s(tr['cover_content']);
    final opinion = s(tr['cover_opinion']);
    if (subject.isEmpty && content.isEmpty && opinion.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;

    Widget row(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.bodySmall?.copyWith(color: AppColors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          );

    final toName = personName(asObj(tr['to_user_id']));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.softOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ក្រដាសសង្ខេប', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          _route(context, s(asObj(tr['from_office_id'])['name']).isEmpty ? '-' : s(asObj(tr['from_office_id'])['name']),
              toName.isEmpty ? 'ថ្នាក់ដឹកនាំ' : toName),
          row('កម្មវត្ថុ', subject),
          row('ខ្លឹមសារ', content),
          row('យោបល់', opinion),
        ],
      ),
    );
  }
}
