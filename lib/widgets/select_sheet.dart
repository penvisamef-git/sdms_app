import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One choice in a [SelectField] / [showSelectSheet].
class Option {
  const Option(this.value, this.label, {this.sub});

  final String value;
  final String label;
  final String? sub;
}

/// Bottom sheet with a search box. Returns the chosen value ('' = cleared), or null when closed.
Future<String?> showSelectSheet(
  BuildContext context, {
  required String title,
  required List<Option> options,
  String selected = '',
  bool allowClear = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _SelectSheet(title: title, options: options, selected: selected, allowClear: allowClear),
  );
}

class _SelectSheet extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.allowClear,
  });

  final String title;
  final List<Option> options;
  final String selected;
  final bool allowClear;

  @override
  State<_SelectSheet> createState() => _SelectSheetState();
}

class _SelectSheetState extends State<_SelectSheet> {
  String _kw = '';

  @override
  Widget build(BuildContext context) {
    final kw = _kw.toLowerCase();
    final list = kw.isEmpty
        ? widget.options
        : widget.options.where((o) => '${o.label} ${o.sub ?? ''}'.toLowerCase().contains(kw)).toList();
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (widget.allowClear && widget.selected.isNotEmpty)
                    TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('សម្អាត')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(hintText: 'ស្វែងរក...', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _kw = v.trim()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('រកមិនឃើញ', style: TextStyle(color: AppColors.muted)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final o = list[i];
                        final on = o.value == widget.selected;
                        return ListTile(
                          title: Text(o.label),
                          subtitle: o.sub == null || o.sub!.isEmpty ? null : Text(o.sub!),
                          trailing: on ? const Icon(Icons.check_circle, color: AppColors.primary) : null,
                          onTap: () => Navigator.pop(context, o.value),
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

/// A form field that looks like a text field and opens a searchable sheet.
class SelectField extends StatelessWidget {
  const SelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint = '-- ជ្រើសរើស --',
    this.enabled = true,
    this.allowClear = true,
  });

  final String label;
  final List<Option> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool enabled;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final match = options.where((o) => o.value == value);
    final text = match.isEmpty ? '' : match.first.label;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: !enabled
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              final r = await showSelectSheet(
                context,
                title: label,
                options: options,
                selected: value,
                allowClear: allowClear,
              );
              if (r != null) onChanged(r);
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        isEmpty: text.isEmpty,
        child: Text(
          text.isEmpty ? hint : text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.isEmpty ? const TextStyle(color: AppColors.muted) : null,
        ),
      ),
    );
  }
}
