import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import '../../widgets/sensor_chart.dart';
import '../../../core/theme/modern_theme.dart';

class LiveMonitorScreen extends StatefulWidget {
  const LiveMonitorScreen({super.key});

  @override
  State<LiveMonitorScreen> createState() => _LiveMonitorScreenState();
}

class _LiveMonitorScreenState extends State<LiveMonitorScreen>
    with SingleTickerProviderStateMixin {
  int _heartRate = 72;
  int _stressLevel = 23;
  int _threatScore = 15;
  Timer? _updateTimer;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _startSimulation();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  void _startSimulation() {
    _updateTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      setState(() {
        final oldThreatScore = _threatScore;
        _heartRate = max(
          60,
          min(120, _heartRate + (Random().nextDouble() - 0.5) * 6).round(),
        );
        _stressLevel = max(
          0,
          min(100, _stressLevel + (Random().nextDouble() - 0.5) * 8).round(),
        );
        _threatScore = max(
          0,
          min(100, _threatScore + (Random().nextDouble() - 0.5) * 5).round(),
        );

        // Trigger scale animation if threat score changed
        if (_threatScore != oldThreatScore) {
          _scaleController.forward(from: 0);
        }
      });
    });
  }

  Color _getThreatScoreColor() {
    if (_threatScore < 30) return AppTheme.safeColor;
    if (_threatScore < 60) return AppTheme.warningColor;
    return AppTheme.dangerColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Camera Feed
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Stack(
                children: [
                  // Video placeholder with gradient
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.textMuted.withValues(alpha: 0.5),
                      ),
                      child: Stack(
                        children: [
                          // Gradient overlay
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.transparent,
                                    AppTheme.backgroundColor.withValues(alpha: 0.8),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // Center content
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.videocam,
                                  size: 32,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Smart Glasses Camera Feed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // LIVE indicator
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.3, end: 1.0),
                                      duration: const Duration(
                                        milliseconds: 1000,
                                      ),
                                      curve: Curves.easeInOut,
                                      builder: (context, value, child) {
                                        return Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: AppTheme.safeColor
                                                .withValues(alpha: value),
                                          ),
                                        );
                                      },
                                      onEnd: () {
                                        setState(() {});
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'LIVE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.safeColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Threat Score Badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _scaleController,
                          curve: Curves.easeOut,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _getThreatScoreColor(),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$_threatScore',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Record Button
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'REC',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Motion Graph
            const SensorChart(
              title: 'Motion Variance',
              color: AppTheme.primaryColor,
              height: 100,
            ),

            const SizedBox(height: 12),

            // Sensor Readings
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.favorite,
                              size: 16,
                              color: AppTheme.dangerColor,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Heart Rate',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$_heartRate',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              'bpm',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              size: 16,
                              color: AppTheme.warningColor,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Stress Level',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$_stressLevel',
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              '%',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Additional Charts
            const SensorChart(
              title: 'Accelerometer X',
              color: Color(0xFF3B9CD9),
              height: 80,
            ),

            const SizedBox(height: 16),

            const SensorChart(
              title: 'Gyroscope Variance',
              color: Color(0xFFFF9F38),
              height: 80,
            ),
          ],
        ),
      ),
    );
  }
}
