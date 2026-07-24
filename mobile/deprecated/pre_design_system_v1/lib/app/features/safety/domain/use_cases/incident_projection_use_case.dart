import '../../../../shared/models/domain_models.dart';
import 'threat_assessment_use_case.dart';

class IncidentProjectionUseCase {
  final ThreatAssessmentUseCase _threatAssessmentUseCase;

  const IncidentProjectionUseCase({
    ThreatAssessmentUseCase threatAssessmentUseCase =
        const ThreatAssessmentUseCase(),
  }) : _threatAssessmentUseCase = threatAssessmentUseCase;

  IncidentRecord fromLiveState({
    required Map<String, dynamic> json,
    required GeoCoordinate currentLocation,
    required double fallbackThreatScore,
    required String Function() nextId,
  }) {
    final createdAt =
        DateTime.tryParse((json['created_at'] ?? '').toString()) ??
        DateTime.now();
    final threat = json['threat_level']?.toString();
    final level = _threatAssessmentUseCase.levelFromBackendValue(
      threat,
      fallbackScore: fallbackThreatScore,
    );

    return IncidentRecord(
      id: (json['id'] ?? nextId()).toString(),
      createdAt: createdAt,
      severity: level,
      summary: (json['title'] ?? json['summary'] ?? 'Incident').toString(),
      location: currentLocation,
      evidenceFiles: const [],
      synced: true,
    );
  }
}
