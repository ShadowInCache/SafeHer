import 'models/dashboard_analytics.dart';
import 'models/dashboard_summary.dart';

abstract class DashboardRepository {
  Future<DashboardSummary> getDashboardSummary();

  /// Backs the Dashboard screen (SRS SCREEN 9). Separate from
  /// [getDashboardSummary] because Home only needs the weekly strip, and
  /// making it pay for a 30-day window, a heatmap and device health on every
  /// launch would be wasteful.
  Future<DashboardAnalytics> getDashboardAnalytics();
}
