import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';

/// Compact trend line with a gradient fill beneath it. Draws in (rises
/// from a flat baseline to the real values) the first time it appears.
class SaSparkline extends StatefulWidget {
  const SaSparkline({required this.values, super.key, this.color = AppColors.violet500, this.height = 48});

  final List<double> values;
  final Color color;
  final double height;

  @override
  State<SaSparkline> createState() => _SaSparklineState();
}

class _SaSparklineState extends State<SaSparkline> {
  bool _appeared = false;
  Timer? _appearTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reducedMotion = AnimationHelpers.reducedMotion(context);
      if (reducedMotion) {
        setState(() => _appeared = true);
      } else {
        _appearTimer = Timer(const Duration(milliseconds: 50), () {
          if (mounted) setState(() => _appeared = true);
        });
      }
    });
  }

  @override
  void dispose() {
    _appearTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) return SizedBox(height: widget.height);

    final minY = widget.values.reduce((a, b) => a < b ? a : b);
    final maxY = widget.values.reduce((a, b) => a > b ? a : b);
    final baseline = minY;

    final spots = List.generate(widget.values.length, (i) {
      final y = _appeared ? widget.values[i] : baseline;
      return FlSpot(i.toDouble(), y);
    });

    return Semantics(
      label: 'Trend sparkline',
      child: RepaintBoundary(
        child: SizedBox(
          height: widget.height,
          child: LineChart(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            LineChartData(
              minY: minY == maxY ? minY - 1 : minY,
              maxY: minY == maxY ? maxY + 1 : maxY,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  barWidth: 2,
                  color: widget.color,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [widget.color.withValues(alpha: 0.3), widget.color.withValues(alpha: 0.0)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
