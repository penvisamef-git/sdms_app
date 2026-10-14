import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/json.dart';
import '../../core/theme.dart';

/// Documents per day of the month (columns).
class DayColumns extends StatelessWidget {
  const DayColumns({super.key, required this.days, this.color = AppColors.primary});

  final List<Json> days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final counts = days.map((d) => asInt(d['count'])).toList();
    final maxY = counts.fold<int>(0, (a, b) => b > a ? b : a);
    final top = (maxY < 4 ? 4 : maxY + (maxY * 0.15).ceil()).toDouble();
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final grid = Theme.of(context).dividerColor;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: top,
          alignment: BarChartAlignment.spaceBetween,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: top <= 6 ? 1 : (top / 4).ceilToDouble(),
            getDrawingHorizontalLine: (_) => FlLine(color: grid, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: top <= 6 ? 1 : (top / 4).ceilToDouble(),
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: muted)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  final day = i + 1;
                  // 1, 5, 10 ... keep the axis calm
                  if (i < 0 || i >= days.length || !(day == 1 || day % 5 == 0)) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text('$day', style: TextStyle(fontSize: 10, color: muted)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final i = group.x;
                final date = i < days.length ? s(days[i]['date']).split('-').reversed.join('/') : '';
                return BarTooltipItem(
                  '$date\n${rod.toY.toInt()} ឯកសារ',
                  const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < counts.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: counts[i].toDouble(),
                    width: counts.length > 20 ? 5 : 8,
                    color: color,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class StackPart {
  const StackPart(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;
}

/// One horizontal stacked bar with a legend of values underneath.
class StackBar extends StatelessWidget {
  const StackBar({super.key, required this.parts});

  final List<StackPart> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (a, p) => a + p.count);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: total == 0
                ? Container(color: AppColors.other.withValues(alpha: 0.4))
                : Row(
                    children: [
                      for (final p in parts.where((p) => p.count > 0))
                        Expanded(
                          flex: p.count,
                          child: Container(
                            margin: const EdgeInsets.only(right: 2),
                            color: p.color,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: p.color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(p.label, style: t.bodyMedium)),
                Text('${p.count}', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                if (total > 0)
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${(p.count * 100 / total).round()}%',
                      textAlign: TextAlign.right,
                      style: t.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
