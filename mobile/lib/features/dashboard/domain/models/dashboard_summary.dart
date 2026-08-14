import '../../../../shared/components/charts/sa_bar_chart.dart';
import '../../../../shared/components/charts/sa_donut_chart.dart';

/// Real aggregation over the signed-in user's own incidents — see
/// `fastapi_app/routers/dashboard.py`. Feeds the Dashboard (Home) screen's
/// "This Week" section; there is no separate analytics screen anymore.
class DashboardSummary {
  const DashboardSummary({required this.weeklyThreatTrend, required this.eventBreakdown});

  final List<SaBarChartDatum> weeklyThreatTrend;
  final List<SaDonutSegment> eventBreakdown;
}
