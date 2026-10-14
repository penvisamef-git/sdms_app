import 'package:flutter/material.dart';

import '../core/format.dart';

/// Date input. [value] is "yyyy-MM-dd" or ''.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final date = parseApiDate(value);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: !enabled
          ? null
          : () async {
              FocusScope.of(context).unfocus();
              final now = DateTime.now();
              final r = await showDatePicker(
                context: context,
                initialDate: date ?? now,
                firstDate: DateTime(2000),
                lastDate: DateTime(now.year + 5),
              );
              if (r != null) onChanged(toApiDate(r));
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: value.isEmpty
              ? const Icon(Icons.calendar_today_outlined, size: 20)
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: enabled ? () => onChanged('') : null,
                ),
        ),
        isEmpty: date == null,
        child: Text(date == null ? '' : formatDate(date)),
      ),
    );
  }
}
