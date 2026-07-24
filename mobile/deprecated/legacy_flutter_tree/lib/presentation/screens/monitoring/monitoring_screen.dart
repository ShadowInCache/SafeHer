import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MonitoringScreen extends ConsumerStatefulWidget {
  const MonitoringScreen({super.key});

  @override
  ConsumerState<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends ConsumerState<MonitoringScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  
  // Sensor data (matches React LiveMonitor)
  int heartRate = 72;
  int stressLevel = 23;
  int threatScore = 15;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
    
    // Simulate real-time data updates
    _startDataSimulation();
  }

  void _startDataSimulation() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          heartRate = math.max(60, math.min(120, heartRate + (math.Random().nextDouble() - 0.5) * 6).round());
          stressLevel = math.max(0, math.min(100, stressLevel + (math.Random().nextDouble() - 0.5) * 8).round());
          threatScore = math.max(0, math.min(100, threatScore + (math.Random().nextDouble() - 0.5) * 5).round());
        });
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  Color _getScoreColor(int score) {
    if (score < 30) return const Color(0xFF10B981);
    if (score < 60) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF0F0F0F),
              Color(0xFF0A0A0A),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Camera Feed Section (matches React camera feed)
                _buildCameraFeed(),
                const SizedBox(height: 16),
                
                // Motion Graph Section
                _buildMotionGraph(),
                const SizedBox(height: 16),
                
                // Sensor Readings (matches React sensor readings)
                _buildSensorReadings(),
                const SizedBox(height: 16),
                
                // Additional Charts
                _buildAdditionalCharts(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Camera Feed Widget (matches React camera feed)
  Widget _buildCameraFeed() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Camera feed placeholder
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam,
                    color: Color(0xFF6B7280),
                    size: 32,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Smart Glasses Camera Feed',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Live indicator
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(
                            alpha: 0.5 + (_pulseController.value * 0.5),
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getScoreColor(threatScore),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                threatScore.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          
          // Record Button
          Positioned(
            bottom: 12,
            right: 12,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  isRecording = !isRecording;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isRecording 
                    ? const Color(0xFFEF4444).withValues(alpha: 0.8)
                    : Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'REC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Motion Graph Widget
  Widget _buildMotionGraph() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Motion Variance',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          
          // Mock waveform
          SizedBox(
            height: 60,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(double.infinity, 60),
                  painter: WaveformPainter(
                    progress: _waveController.value,
                    color: const Color(0xFF8B5CF6),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Sensor Readings Widget (matches React sensor readings)
  Widget _buildSensorReadings() {
    return Row(
      children: [
        Expanded(
          child: _buildSensorCard(
            icon: Icons.favorite,
            iconColor: const Color(0xFFEF4444),
            title: 'Heart Rate',
            value: heartRate.toString(),
            unit: 'bpm',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSensorCard(
            icon: Icons.psychology,
            iconColor: const Color(0xFFF59E0B),
            title: 'Stress Level', 
            value: stressLevel.toString(),
            unit: '%',
          ),
        ),
      ],
    );
  }

  // Individual Sensor Card
  Widget _buildSensorCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: iconColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF), 
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Additional Charts Widget
  Widget _buildAdditionalCharts() {
    return Column(
      children: [
        _buildSimpleChart(
          title: 'Accelerometer X',
          color: const Color(0xFF3B82F6),
        ),
        const SizedBox(height: 12),
        _buildSimpleChart(
          title: 'Gyroscope Variance', 
          color: const Color(0xFFF59E0B),
        ),
      ],
    );
  }

  // Simple Chart Widget
  Widget _buildSimpleChart({
    required String title,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A2A2A),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          
          SizedBox(
            height: 40,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(double.infinity, 40),
                  painter: SimpleChartPainter(
                    progress: _waveController.value,
                    color: color,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Waveform
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;

  WaveformPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final waveHeight = size.height * 0.3;
    final centerY = size.height / 2;

    for (int i = 0; i < size.width; i++) {
      final x = i.toDouble();
      final wave1 = math.sin((x / 20) + (progress * math.pi * 4)) * waveHeight;
      final wave2 = math.sin((x / 30) + (progress * math.pi * 6)) * waveHeight * 0.5;
      final y = centerY + wave1 + wave2;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Custom Painter for Simple Charts
class SimpleChartPainter extends CustomPainter {
  final double progress;
  final Color color;

  SimpleChartPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;

    for (int i = 0; i < size.width; i++) {
      final x = i.toDouble();
      final noise = (math.Random(i).nextDouble() - 0.5) * size.height * 0.6;
      final y = centerY + noise;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
