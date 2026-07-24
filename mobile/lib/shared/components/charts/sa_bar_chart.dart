import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_typography.dart';
import '../../models/threat_level.dart';

class SaBarChartDatum {
  const SaBarChartDatum({required this.label, required this.value, required this.level});

  final String label;
  final double value;
  final ThreatLevel level;
}

/// Grouped bar chart with threat-level colour coding. Tapping a bar invokes
/// [onBarTap] with its index so the caller can show a detail sheet.
class SaBarChart extends StatelessWidget {
  const SaBarChart({required this.data, super.key, this.height = 200, this.onBarTap});

  final List<SaBarChartDatum> data;
  final double height;
  final ValueChanged<int>? onBarTap;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return SizedBox(height: height);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final maxValue = data.map((d) => d.value).reduce((a, b) => a > b ? a : b);

    return Semantics(
      label: 'Bar chart with ${data.length} bars',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: BarChart(
            swapAnimationDuration: const Duration(milliseconds: 350),
            BarChartData(
              maxY: maxValue == 0 ? 1 : maxValue * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= data.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(data[index].label, style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6))),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent || response?.spot == null) return;
                  onBarTap?.call(response!.spot!.touchedBarGroupIndex);
                },
              ),
              barGroups: [
                for (var i = 0; i < data.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].value,
                        color: data[i].level.color(context),
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
