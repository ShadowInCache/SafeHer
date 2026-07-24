import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';

/// The 4-tier threat state used across the gauge, chips, cards, and alerts.
/// Bands per the design spec: SAFE 0.00–0.40, CAUTION 0.41–0.60,
/// ELEVATED 0.61–0.74, DANGER 0.75–1.00.
enum ThreatLevel {
  safe,
  caution,
  elevated,
  danger;

  static ThreatLevel fromScore(double score) {
    if (score >= 0.75) return ThreatLevel.danger;
    if (score >= 0.61) return ThreatLevel.elevated;
    if (score >= 0.41) return ThreatLevel.caution;
    return ThreatLevel.safe;
  }

  String get label => switch (this) {
    ThreatLevel.safe => 'SAFE',
    ThreatLevel.caution => 'CAUTION',
    ThreatLevel.elevated => 'ELEVATED',
    ThreatLevel.danger => 'DANGER',
  };

  Color color(BuildContext context) {
    final saColors = context.saColors;
    return switch (this) {
      ThreatLevel.safe => saColors.threatSafe,
      ThreatLevel.caution => saColors.threatCaution,
      ThreatLevel.elevated => saColors.threatElevated,
      ThreatLevel.danger => saColors.threatDanger,
    };
  }

  Color glowColor(BuildContext context) {
    final saColors = context.saColors;
    return switch (this) {
      ThreatLevel.safe => saColors.threatSafeGlow,
      ThreatLevel.caution => saColors.threatCautionGlow,
      ThreatLevel.elevated => saColors.threatElevatedGlow,
      ThreatLevel.danger => saColors.threatDangerGlow,
    };
  }
}
