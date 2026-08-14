class ThreatSnapshot {
  const ThreatSnapshot({
    required this.score,
    required this.lastUpdated,
    this.motionScore,
    this.audioScore,
    this.visionScore,
  });

  /// 0.0–1.0
  final double score;
  final DateTime lastUpdated;

  /// Per-modality breakdown — null unless the backend actually returns a
  /// component score for that modality (it doesn't today; `/alerts/live`
  /// only exposes the fused overall score).
  final double? motionScore;
  final double? audioScore;
  final double? visionScore;
}

/// Dashboard-specific summary — just the live fused threat reading.
/// Identity (name), devices, live-monitoring connection, recent alerts,
/// and weekly trends are NOT duplicated here; the screen reads those from
/// their own shared providers so they can never drift from what those
/// features' own screens show.
///
/// [threat] is null whenever there's genuinely no backend data to show
/// yet (no wearable has ever reported a score). The screen renders an
/// honest waiting state rather than a fabricated reading.
class HomeSummary {
  const HomeSummary({required this.threat});

  final ThreatSnapshot? threat;
}
