import 'package:flutter/material.dart';
import 'dart:math';
import '../../core/theme/modern_theme.dart';

class SensorChart extends StatefulWidget {
  final String title;
  final Color color;
  final double height;

  const SensorChart({
    super.key,
    required this.title,
    required this.color,
    this.height = 120,
  });

  @override
  State<SensorChart> createState() => _SensorChartState();
}

class _SensorChartState extends State<SensorChart> {
  late List<double> _data;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    // Initialize with 40 data points, range 20-80
    _data = List.generate(40, (i) => _random.nextDouble() * 60 + 20);
    _startSimulation();
  }

  void _startSimulation() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() {
          // Remove first element
          _data.removeAt(0);
          // Add new value based on last value with random variation
          final lastValue = _data.isNotEmpty ? _data.last : 50.0;
          var newValue = lastValue + (_random.nextDouble() - 0.5) * 20;
          // Clamp between 5 and 95
          newValue = max(5.0, min(95.0, newValue));
          _data.add(newValue);
        });
        _startSimulation();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentValue = _data.isNotEmpty ? _data.last : 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                currentValue.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: widget.height,
            child: CustomPaint(
              painter: _ChartPainter(data: _data, color: widget.color),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _ChartPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final y = (height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(width, y), gridPaint);
    }

    if (data.isEmpty) return;

    // Create gradient for fill
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
    );

    // Build path for line
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * width;
      // Use fixed 0-100 range
      final y = height - (data[i] / 100) * height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Create fill path
    final fillPath = Path.from(path);
    final lastX = width;
    final lastY = height - (data.last / 100) * height;
    fillPath.lineTo(lastX, height);
    fillPath.lineTo(0, height);
    fillPath.close();

    // Draw gradient fill
    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw current value dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(lastX, lastY), 4, dotPaint);

    // Draw dot outline
    final dotOutlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(Offset(lastX, lastY), 4, dotOutlinePaint);
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) => true;
}
