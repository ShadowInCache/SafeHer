import '../../../core/theme/app_colors.dart';
import '../../../shared/components/charts/sa_bar_chart.dart';
import '../../../shared/components/charts/sa_donut_chart.dart';
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
    );
  }
}
