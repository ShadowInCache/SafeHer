import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_extensions.dart';

/// Location-frequency heat grid — no map dependency, just a coloured cell
/// grid. [grid] rows each hold intensities in 0.0–1.0.
class SaHeatGrid extends StatelessWidget {
  const SaHeatGrid({required this.grid, super.key, this.height = 160});

  final List<List<double>> grid;
  final double height;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Semantics(
      label: 'Location frequency heat grid',
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size(constraints.maxWidth, height),
              painter: _HeatGridPainter(grid: grid, trackColor: saColors.surfaceHighest),
            );
          },
        ),
      ),
    );
  }
}

class _HeatGridPainter extends CustomPainter {
  _HeatGridPainter({required this.grid, required this.trackColor});

  final List<List<double>> grid;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (grid.isEmpty || grid.first.isEmpty) return;
    final rows = grid.length;
    final cols = grid.first.length;
    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;
    const gap = 2.0;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final intensity = grid[r][c].clamp(0.0, 1.0);
        final color = intensity == 0
            ? trackColor
            : Color.lerp(AppColors.violet900, AppColors.coral500, intensity)!;
        final rect = Rect.fromLTWH(
          c * cellWidth + gap / 2,
          r * cellHeight + gap / 2,
          cellWidth - gap,
          cellHeight - gap,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatGridPainter oldDelegate) => oldDelegate.grid != grid;
}
