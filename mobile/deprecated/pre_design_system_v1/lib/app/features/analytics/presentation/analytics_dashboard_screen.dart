import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class AnalyticsDashboardScreen extends ConsumerWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final total = max(1, safety.incidents.length);
    final warningCount = safety.incidents
        .where((i) => i.severity.name == 'warning')
        .length;
    final dangerCount = safety.incidents
        .where((i) => i.severity.name == 'danger')
        .length;
    final safeCount = total - warningCount - dangerCount;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Analytics Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  context,
                  title: 'Weekly Incidents',
                  value: '${(total * 0.6).round()}',
                  trend: '+12%',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  context,
                  title: 'Monthly Incidents',
                  value: '$total',
                  trend: '-8%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Threat Distribution',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _trendRow('Safe', safeCount / total, PremiumTheme.safe),
                _trendRow(
                  'Warning',
                  warningCount / total,
                  PremiumTheme.warning,
                ),
                _trendRow('Danger', dangerCount / total, PremiumTheme.danger),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modality Trends',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _trendRow('Motion anomalies', 0.63, PremiumTheme.accent),
                _trendRow('Voice aggression', 0.41, PremiumTheme.warning),
                _trendRow('Weapon detections', 0.29, PremiumTheme.danger),
                _trendRow('Suspicious person cues', 0.37, Colors.purpleAccent),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unsafe Area Heatmap Summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Top hotspot cluster: Downtown transport corridor (19:00-22:00).',
                ),
                const Text(
                  'Risk-weighted safe route recommendation saved for evening commute.',
                ),
                const SizedBox(height: 10),
                Container(
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF22C55E),
                        Color(0xFFF59E0B),
                        Color(0xFFEF4444),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personalized Recommendations',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.recommend),
                  title: Text(
                    'Increase glove sensitivity by 5% during late commute hours.',
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.recommend),
                  title: Text(
                    'Enable automatic live streaming for danger-level incidents.',
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.recommend),
                  title: Text(
                    'Review and prioritize two guardian contacts for faster escalation.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String trend,
  }) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(trend, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _trendRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text('${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value,
            color: color,
            minHeight: 7,
            borderRadius: BorderRadius.circular(20),
          ),
        ],
      ),
    );
  }
}
