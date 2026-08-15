import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/theme_extensions.dart';

/// One aggregated incident location. [lat]/[lng] are the south-west corner of
/// a server-side grid cell (~1.1 km), never a precise fix — see
/// `HEATMAP_CELL_DEGREES` in `fastapi_app/routers/dashboard.py`.
@immutable
class SaHeatCell {
  const SaHeatCell({required this.lat, required this.lng, required this.weight});

  final double lat;
  final double lng;

  /// Number of incident locations that fell inside this cell.
  final int weight;
}

/// Incident density map, drawn as a grid rather than a real basemap.
///
/// SRS SCREEN 9 offers a choice between this and a `google_maps_flutter`
/// snapshot. The grid is the deliberate pick: it needs no Maps API key, no
/// network round trip and no tile cache, and — the reason that actually
/// matters — it cannot accidentally render a recognisable street corner where
/// a woman was attacked. The cells are already coarse; the abstraction keeps
/// them that way.
class SaHeatGrid extends StatelessWidget {
  const SaHeatGrid({
    required this.cells,
    super.key,
    this.height = 180,
    this.columns = 12,
    this.rows = 7,
  });

  final List<SaHeatCell> cells;
  final double height;

  /// Resolution of the rendered lattice. The geographic bounding box of
  /// [cells] is stretched to fill it, so this controls appearance only — it
  /// never changes how coarsely locations were aggregated.
  final int columns;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final total = cells.fold<int>(0, (sum, cell) => sum + cell.weight);
    return Semantics(
      label: cells.isEmpty
          ? 'Incident location map, no locations recorded'
          : 'Incident location map, $total incident locations across ${cells.length} areas',
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _HeatGridPainter(
              cells: cells,
              columns: columns,
              rows: rows,
              emptyColor: context.saColors.glassBorder,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeatGridPainter extends CustomPainter {
  _HeatGridPainter({
    required this.cells,
    required this.columns,
    required this.rows,
    required this.emptyColor,
  });

  final List<SaHeatCell> cells;
  final int columns;
  final int rows;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 3.0;
    final cellWidth = (size.width - gap * (columns - 1)) / columns;
    final cellHeight = (size.height - gap * (rows - 1)) / rows;
    final radius = Radius.circular(AppRadius.sm);

    // Accumulate weight per rendered tile first, so two geographic cells
    // that land on the same tile add up instead of overpainting.
    final buckets = List<int>.filled(columns * rows, 0);
    var maxWeight = 0;

    if (cells.isNotEmpty) {
      var minLat = cells.first.lat;
      var maxLat = cells.first.lat;
      var minLng = cells.first.lng;
      var maxLng = cells.first.lng;
      for (final cell in cells) {
        minLat = math.min(minLat, cell.lat);
        maxLat = math.max(maxLat, cell.lat);
        minLng = math.min(minLng, cell.lng);
        maxLng = math.max(maxLng, cell.lng);
      }
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;

      for (final cell in cells) {
        // A degenerate span means every incident happened in one area; put
        // it in the middle rather than dividing by zero.
        final fx = lngSpan == 0 ? 0.5 : (cell.lng - minLng) / lngSpan;
        // Latitude increases northward, screen y increases downward.
        final fy = latSpan == 0 ? 0.5 : 1 - (cell.lat - minLat) / latSpan;

        final column = (fx * (columns - 1)).round().clamp(0, columns - 1);
        final row = (fy * (rows - 1)).round().clamp(0, rows - 1);
        final index = row * columns + column;
        buckets[index] += cell.weight;
        maxWeight = math.max(maxWeight, buckets[index]);
      }
    }

    final paint = Paint()..style = PaintingStyle.fill;
    final glow = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final rect = RRect.fromLTRBR(
          column * (cellWidth + gap),
          row * (cellHeight + gap),
          column * (cellWidth + gap) + cellWidth,
          row * (cellHeight + gap) + cellHeight,
          radius,
        );
        final weight = buckets[row * columns + column];

        if (weight == 0) {
          canvas.drawRRect(rect, paint..color = emptyColor);
          continue;
        }

        // Normalised against the busiest tile, so a single-incident map
        // reads as one hot cell rather than a uniformly cool one.
        final intensity = maxWeight == 1 ? 1.0 : weight / maxWeight;
        final color = _heatColor(intensity);
        canvas.drawRRect(rect, glow..color = color.withValues(alpha: 0.45 * intensity));
        canvas.drawRRect(rect, paint..color = color);
      }
    }
  }

  /// Cool violet for isolated incidents through to coral for the hotspot —
  /// the same threat ramp the rest of the app uses, so a user who has learnt
  /// what coral means on the gauge reads this map correctly on sight.
  Color _heatColor(double intensity) {
    if (intensity < 0.5) {
      return Color.lerp(AppColors.violet700, AppColors.violet400, intensity / 0.5)!;
    }
    return Color.lerp(AppColors.violet400, AppColors.coral500, (intensity - 0.5) / 0.5)!;
  }

  @override
  bool shouldRepaint(_HeatGridPainter oldDelegate) =>
      oldDelegate.cells != cells ||
      oldDelegate.columns != columns ||
      oldDelegate.rows != rows ||
      oldDelegate.emptyColor != emptyColor;
}
