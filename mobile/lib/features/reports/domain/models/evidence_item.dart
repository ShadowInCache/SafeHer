enum EvidenceType { video, audio, photo }

/// One piece of captured evidence attached to a report.
class EvidenceItem {
  const EvidenceItem({
    required this.id,
    required this.type,
    required this.url,
    this.thumbnailUrl,
    this.durationLabel,
  });

  final String id;
  final EvidenceType type;

  /// Playable/viewable media URL (video/audio stream, or the full-res photo).
  final String url;

  /// Null for audio (rendered as a static waveform card instead of a
  /// thumbnail image).
  final String? thumbnailUrl;

  /// Pre-formatted "1:24" style duration, null for photos.
  final String? durationLabel;
}
