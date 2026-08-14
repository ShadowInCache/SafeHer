enum TimelineEventType { sensorEvent, aiDetection, alertTrigger, evidenceCaptured, contactNotified }

/// One entry in a report's chronological event timeline.
class TimelineEvent {
  const TimelineEvent({
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    this.confidence,
  });

  final TimelineEventType type;
  final String title;
  final String description;

  /// Pre-formatted for display (e.g. "14:32:07") — the mock/remote source
  /// already has this in local time, no timezone math needed here.
  final String timestamp;

  /// 0.0–1.0, null when the event type has no associated confidence score
  /// (e.g. contactNotified).
  final double? confidence;
}
