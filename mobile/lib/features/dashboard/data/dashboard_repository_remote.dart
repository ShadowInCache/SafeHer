import 'dart:ui';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/dashboard_repository.dart';
import '../domain/models/dashboard_summary.dart';

/// `fastapi_app`-backed [DashboardRepository] — `GET /api/v1/dashboard/summary`.
/// Every number here is a real aggregation over this user's own incidents
/// (see `fastapi_app/routers/dashboard.py`). There is no gamified safety
/// score and no location heatmap on the backend today, so neither is
/// modeled here — inventing either would be exactly the kind of
/// fabricated chart this build explicitly avoids.
class DashboardRepositoryRemote implements DashboardRepository {
  DashboardRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Color _colorForLevel(String level) => switch (level.toLowerCase()) {
    'critical' => AppColors.danger500,
    'high' => AppColors.threatElevated,
    'medium' => AppColors.warning500,
    'low' => AppColors.success500,
    _ => AppColors.neutral400,
  };

  ThreatLevel _barLevelForCount(int count) {
    if (count >= 3) return ThreatLevel.danger;
    if (count == 2) return ThreatLevel.elevated;
    if (count == 1) return ThreatLevel.caution;
    return ThreatLevel.safe;
  }

  String _shortDay(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    final response = await _apiClient.dio.get('/dashboard/summary');
    final json = response.data as Map<String, dynamic>;

    final breakdown = (json['threat_level_breakdown'] as Map<String, dynamic>?) ?? const {};
    final last7Days = (json['incidents_last_7_days'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    return DashboardSummary(
      weeklyThreatTrend: [
        for (final day in last7Days)
          SaBarChartDatum(
            label: _shortDay(day['date'] as String),
            value: (day['count'] as num).toDouble(),
            level: _barLevelForCount(day['count'] as int),
          ),
      ],
      eventBreakdown: [
        for (final entry in breakdown.entries)
          SaDonutSegment(label: entry.key, value: (entry.value as num).toDouble(), color: _colorForLevel(entry.key)),
      ],
    );
  }
}
