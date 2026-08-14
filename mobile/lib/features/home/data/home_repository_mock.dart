import '../domain/home_repository.dart';
import '../domain/models/home_summary.dart';

class HomeRepositoryMock implements HomeRepository {
  @override
  Future<HomeSummary> getHomeSummary() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return HomeSummary(
      threat: ThreatSnapshot(
        score: 0.28,
        motionScore: 0.2,
        audioScore: 0.15,
        visionScore: 0.35,
        lastUpdated: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    );
  }
}
