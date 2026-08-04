import '../../../../shared/components/cards/sa_stat_card.dart';
import '../../../../shared/components/charts/sa_bar_chart.dart';
import '../../../../shared/components/charts/sa_donut_chart.dart';
import '../../../../shared/components/icons/sa_icon.dart';

class DashboardStatItem {
  const DashboardStatItem({required this.label, required this.value, this.trend, this.icon});

  final String label;
  final String value;
  final SaTrendDirection? trend;
  final SaIconGlyph? icon;
}

/// Analytics snapshot for the Dashboard screen — weekly threat trend,
/// event-type breakdown, safety score history, and an incident heat grid,
/// alongside a handful of headline stats.
class DashboardSummary {
  const DashboardSummary({
    required this.stats,
    required this.weeklyThreatTrend,
    required this.eventBreakdown,
    required this.safetyScoreTrend,
    required this.locationHeatGrid,
  });

  final List<DashboardStatItem> stats;
  final List<SaBarChartDatum> weeklyThreatTrend;
  final List<SaDonutSegment> eventBreakdown;
  final List<double> safetyScoreTrend;
  final List<List<double>> locationHeatGrid;
}
