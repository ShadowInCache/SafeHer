import 'package:flutter/material.dart';
import '../../core/theme/modern_theme.dart';

enum ThreatLevel { safe, low, medium, high, critical }

class ThreatBanner extends StatelessWidget {
  final ThreatLevel level;
  final int score;

  const ThreatBanner({super.key, required this.level, required this.score});

  Map<String, dynamic> _getConfig() {
    switch (level) {
      case ThreatLevel.safe:
        return {
          'label': 'All Clear',
          'color': AppTheme.safeColor,
          'icon': Icons.shield_outlined,
        };
      case ThreatLevel.low:
        return {
          'label': 'Low Risk',
          'color': AppTheme.safeColor,
          'icon': Icons.shield,
        };
      case ThreatLevel.medium:
        return {
          'label': 'Moderate Risk',
          'color': AppTheme.warningColor,
          'icon': Icons.warning_amber,
        };
      case ThreatLevel.high:
        return {
          'label': 'High Risk',
          'color': AppTheme.dangerColor,
          'icon': Icons.error_outline,
        };
      case ThreatLevel.critical:
        return {
          'label': 'CRITICAL',
          'color': AppTheme.criticalColor,
          'icon': Icons.dangerous,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();
    final color = config['color'] as Color;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(
        children: [
          Icon(config['icon'], color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config['label'],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Threat Score: $score/100',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
