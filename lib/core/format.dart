import 'package:intl/intl.dart';

import 'json.dart';

const khMonths = [
  'មករា', 'កុម្ភៈ', 'មីនា', 'មេសា', 'ឧសភា', 'មិថុនា',
  'កក្កដា', 'សីហា', 'កញ្ញា', 'តុលា', 'វិច្ឆិកា', 'ធ្នូ',
];

DateTime? _parse(dynamic value) {
  if (value == null || value == '') return null;
  return DateTime.tryParse(s(value))?.toLocal();
}

/// 05/09/2026
String formatDate(dynamic value) {
  final d = _parse(value);
  return d == null ? '-' : DateFormat('dd/MM/yyyy').format(d);
}

/// 05/09/2026 14:30
String formatDateTime(dynamic value) {
  final d = _parse(value);
  return d == null ? '-' : DateFormat('dd/MM/yyyy HH:mm').format(d);
}

/// yyyy-MM-dd, what the API expects for plain dates.
String toApiDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// ISO string from the API -> DateTime for a date picker (null when empty).
DateTime? parseApiDate(dynamic value) => _parse(value);

String formatBytes(dynamic bytes) {
  final b = asInt(bytes);
  if (b <= 0) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// hours -> "45 នាទី" / "3.5 ម៉ោង" / "2.1 ថ្ងៃ"
String formatHours(dynamic h) {
  final v = asDouble(h);
  if (v == null) return '-';
  if (v < 1) return '${(v * 60).round()} នាទី';
  if (v < 24) return '${v.toStringAsFixed(1)} ម៉ោង';
  return '${(v / 24).toStringAsFixed(1)} ថ្ងៃ';
}

/// 1284 -> "1,284" · 12900 -> "12.9K"
String formatNumber(dynamic n) {
  final v = asInt(n);
  if (v >= 1000000) return '${(v / 1e6).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
  if (v >= 10000) return '${(v / 1e3).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
  return NumberFormat('#,###').format(v);
}

/// "2026-09" for right now in Phnom Penh time (UTC+7), the same clock the API uses.
String currentMonthValue() {
  final d = DateTime.now().toUtc().add(const Duration(hours: 7));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

/// "2026-09" + 1 -> "2026-10"
String shiftMonth(String value, int delta) {
  final parts = value.split('-');
  final d = DateTime.utc(int.parse(parts[0]), int.parse(parts[1]) + delta, 1);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

/// "2026-09" -> "កញ្ញា 2026"
String monthLabel(String value) {
  final parts = value.split('-');
  if (parts.length != 2) return '';
  final m = int.tryParse(parts[1]) ?? 0;
  if (m < 1 || m > 12) return '';
  return '${khMonths[m - 1]} ${parts[0]}';
}
