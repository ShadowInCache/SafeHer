import '../../../shared/components/cards/sa_stat_card.dart';
import '../../../shared/models/threat_level.dart';
import '../domain/home_repository.dart';
import '../domain/models/home_summary.dart';

class HomeRepositoryMock implements HomeRepository {
  @override
  Future<HomeSummary> getHomeSummary() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return HomeSummary(
      userName: 'Priya',
      hasUnreadAlerts: true,
      threat: ThreatSnapshot(
        score: 0.28,
        motionScore: 0.2,
        audioScore: 0.15,
        visionScore: 0.35,
        lastUpdated: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
      devices: const [
        DeviceSummary(id: 'ring', name: 'Smart Ring', batteryPercent: 0.82, signalStrength: 3, isOnline: true),
        DeviceSummary(id: 'glasses', name: 'Safety Glasses', batteryPercent: 0.46, signalStrength: 2, isOnline: true),
        DeviceSummary(id: 'pendant', name: 'Pendant', batteryPercent: 0.09, signalStrength: 1, isOnline: false),
      ],
      waveformPreview: List.generate(32, (i) => (i % 6) / 8),
      motionPreview: List.generate(30, (i) => 0.4 + 0.3 * (i.isEven ? 1 : -1) * (i / 30)),
      recentAlerts: const [
        AlertSummary(
          id: '1',
          title: 'Elevated motion detected',
          timestamp: '2h ago',
          level: ThreatLevel.elevated,
          summary: 'Sudden acceleration spike near Elm Street.',
        ),
        AlertSummary(
          id: '2',
          title: 'Routine check-in',
          timestamp: '1d ago',
          level: ThreatLevel.safe,
          summary: 'All monitored signals within normal range.',
        ),
        AlertSummary(
          id: '3',
          title: 'Loud noise detected',
          timestamp: '2d ago',
          level: ThreatLevel.caution,
          summary: 'Brief audio spike while walking home.',
        ),
      ],
      safetyScore: const SafetyScoreSummary(score: 87, streakDays: 12, trend: SaTrendDirection.up),
    );
  }
}
