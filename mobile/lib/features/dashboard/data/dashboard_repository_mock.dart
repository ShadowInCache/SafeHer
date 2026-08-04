import '../../../core/theme/app_colors.dart';
import '../../../shared/components/cards/sa_stat_card.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/dashboard_repository.dart';
import '../domain/models/dashboard_summary.dart';

const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weeklyScores = [0.22, 0.35, 0.18, 0.48, 0.65, 0.3, 0.15];

class DashboardRepositoryMock implements DashboardRepository {
  @override
  Future<DashboardSummary> getDashboardSummary() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return DashboardSummary(
      stats: const [
        DashboardStatItem(label: 'Total Alerts', value: '14', trend: SaTrendDirection.down, icon: SaIconGlyph.bell),
        DashboardStatItem(label: 'Avg Response', value: '42s', trend: SaTrendDirection.up, icon: SaIconGlyph.monitorPulse),
        DashboardStatItem(label: 'Safe Streak', value: '12d', trend: SaTrendDirection.up, icon: SaIconGlyph.shield),
        DashboardStatItem(label: 'Resolved', value: '11/14', trend: SaTrendDirection.flat, icon: SaIconGlyph.check),
      ],
      weeklyThreatTrend: [
        for (var i = 0; i < _weekdayLabels.length; i++)
          SaBarChartDatum(label: _weekdayLabels[i], value: _weeklyScores[i], level: ThreatLevel.fromScore(_weeklyScores[i])),
      ],
      eventBreakdown: const [
        SaDonutSegment(label: 'Motion', value: 6, color: AppColors.violet500),
        SaDonutSegment(label: 'Audio', value: 4, color: AppColors.coral500),
        SaDonutSegment(label: 'Vision', value: 3, color: AppColors.warning500),
        SaDonutSegment(label: 'Manual SOS', value: 1, color: AppColors.danger500),
      ],
      safetyScoreTrend: const [72, 75, 70, 78, 82, 85, 80, 83, 87, 84, 88, 90, 87, 91],
      locationHeatGrid: [
        [0.1, 0.4, 0.2, 0.0],
        [0.3, 0.6, 0.1, 0.2],
        [0.0, 0.2, 0.5, 0.1],
        [0.2, 0.1, 0.0, 0.3],
        [0.5, 0.7, 0.3, 0.1],
        [0.1, 0.0, 0.2, 0.0],
        [0.0, 0.1, 0.1, 0.0],
      ],
    );
  }
}
