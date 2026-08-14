/// One GPS fix captured during an incident, in chronological order — the
/// full list renders as a numbered-marker trail with a connecting polyline.
class GpsBreadcrumb {
  const GpsBreadcrumb({required this.latitude, required this.longitude, required this.timestamp});

  final double latitude;
  final double longitude;

  /// Pre-formatted for display (e.g. "14:32:07").
  final String timestamp;
}
