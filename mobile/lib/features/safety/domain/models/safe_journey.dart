/// An in-progress or finished Safe Journey, as owned by the backend.
/// The app never invents a journey locally — if there is no active journey on
/// the server, the UI shows the "start one" state.
class SafeJourney {
  const SafeJourney({
    required this.id,
    required this.destinationLabel,
    required this.expectedDurationMinutes,
    required this.status,
    required this.startedAt,
    required this.expectedArrivalAt,
    required this.contactIds,
    this.destinationLat,
    this.destinationLng,
    this.checkInIntervalMinutes,
    this.lastCheckInAt,
    this.endedAt,
  });

  final String id;
  final String destinationLabel;
  final double? destinationLat;
  final double? destinationLng;
  final int expectedDurationMinutes;
  final int? checkInIntervalMinutes;
  final JourneyStatus status;
  final DateTime startedAt;
  final DateTime expectedArrivalAt;
  final DateTime? lastCheckInAt;
  final DateTime? endedAt;
  final List<String> contactIds;

  bool get isInProgress => status == JourneyStatus.active || status == JourneyStatus.overdue;

  /// Negative once the deadline has passed.
  Duration remaining(DateTime now) => expectedArrivalAt.difference(now);

  bool hasRunOutOfTime(DateTime now) => status == JourneyStatus.active && !now.isBefore(expectedArrivalAt);
}

enum JourneyStatus {
  active,
  arrived,
  cancelled,
  overdue;

  static JourneyStatus fromWire(String value) => switch (value) {
    'arrived' => JourneyStatus.arrived,
    'cancelled' => JourneyStatus.cancelled,
    'overdue' => JourneyStatus.overdue,
    _ => JourneyStatus.active,
  };

  String get label => switch (this) {
    JourneyStatus.active => 'In progress',
    JourneyStatus.arrived => 'Arrived safely',
    JourneyStatus.cancelled => 'Cancelled',
    JourneyStatus.overdue => 'Overdue',
  };
}

/// One real recorded GPS point from a journey.
class JourneyBreadcrumb {
  const JourneyBreadcrumb({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyMetres,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final double? accuracyMetres;
}
