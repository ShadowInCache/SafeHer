import '../../../../shared/models/domain_models.dart';

class ThreatAssessmentUseCase {
  const ThreatAssessmentUseCase();

  double parseConfidence(
    Map<String, dynamic> data, {
    required double fallbackThreatScore,
  }) {
    final confidenceValue = (data['confidence'] as num?)?.toDouble();
    if (confidenceValue != null) {
      if (confidenceValue > 1) {
        return (confidenceValue / 100).clamp(0.0, 1.0).toDouble();
      }
      return confidenceValue.clamp(0.0, 1.0).toDouble();
    }

    final scoreValue = (data['threat_score'] as num?)?.toDouble();
    if (scoreValue != null) {
      return (scoreValue / 100).clamp(0.0, 1.0).toDouble();
    }

    return (fallbackThreatScore / 100).clamp(0.0, 1.0).toDouble();
  }

  ThreatLevelState levelFromScore(double score) {
    if (score >= 70) {
      return ThreatLevelState.danger;
    }
    if (score >= 35) {
      return ThreatLevelState.warning;
    }
    return ThreatLevelState.safe;
  }

  ThreatLevelState levelFromBackendValue(
    String? value, {
    required double fallbackScore,
  }) {
    switch (value?.toLowerCase()) {
      case 'critical':
      case 'high':
      case 'danger':
        return ThreatLevelState.danger;
      case 'medium':
      case 'warning':
        return ThreatLevelState.warning;
      case 'low':
      case 'safe':
        return ThreatLevelState.safe;
      default:
        return levelFromScore(fallbackScore);
    }
  }
}
