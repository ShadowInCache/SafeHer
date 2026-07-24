import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Real-time audio waveform. [amplitudes] holds up to [barCount] samples in
/// the range 0.0–1.0 (oldest first); bar colour interpolates emerald→coral
/// as amplitude rises. The caller is responsible for pushing new samples
/// (typically at ~30fps from a WebSocket/MQTT stream); this widget only
/// paints whatever it's given.
class SaWaveform extends StatelessWidget {
  const SaWaveform({required this.amplitudes, super.key, this.height = 64, this.barCount = 64});

  final List<double> amplitudes;
  final double height;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Audio waveform',
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size(constraints.maxWidth, height),
              painter: _WaveformPainter(amplitudes: amplitudes, barCount: barCount),
            );
          },
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.amplitudes, required this.barCount});

  final List<double> amplitudes;
  final int barCount;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / barCount;
    final gap = barWidth * 0.3;
    final effectiveWidth = barWidth - gap;

    final samples = amplitudes.length >= barCount
        ? amplitudes.sublist(amplitudes.length - barCount)
        : [...List.filled(barCount - amplitudes.length, 0.0), ...amplitudes];

    for (var i = 0; i < barCount; i++) {
      final amplitude = samples[i].clamp(0.0, 1.0);
      final barHeight = (size.height * amplitude).clamp(2.0, size.height);
      final color = Color.lerp(AppColors.success500, AppColors.coral500, amplitude)!;
      final paint = Paint()..color = color;
      final left = i * barWidth + gap / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, (size.height - barHeight) / 2, effectiveWidth, barHeight),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => oldDelegate.amplitudes != amplitudes;
}
