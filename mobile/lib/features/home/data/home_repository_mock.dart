import '../../../shared/components/cards/sa_stat_card.dart';
import '../domain/home_repository.dart';
import '../domain/models/home_summary.dart';

class HomeRepositoryMock implements HomeRepository {
  @override
  Future<HomeSummary> getHomeSummary() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return HomeSummary(
      hasUnreadAlerts: true,
      threat: ThreatSnapshot(
        score: 0.28,
        motionScore: 0.2,
        audioScore: 0.15,
        visionScore: 0.35,
        lastUpdated: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      waveformPreview: List.generate(32, (i) => (i % 6) / 8),
      motionPreview: List.generate(30, (i) => 0.4 + 0.3 * (i.isEven ? 1 : -1) * (i / 30)),
      safetyScore: const SafetyScoreSummary(score: 87, streakDays: 12, trend: SaTrendDirection.up),
    );
  }
}
