import '../../../core/network/api_client.dart';
import '../domain/models/safe_journey.dart';
import '../domain/safety_repository.dart';

/// `fastapi_app`-backed [JourneyRepository] — `/api/v1/journeys/*`.
class JourneyRepositoryRemote implements JourneyRepository {
  JourneyRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _basePath = '/journeys';

  SafeJourney _fromJson(Map<String, dynamic> json) => SafeJourney(
    id: json['id'] as String,
    destinationLabel: json['destination_label'] as String,
    destinationLat: (json['destination_lat'] as num?)?.toDouble(),
    destinationLng: (json['destination_lng'] as num?)?.toDouble(),
    expectedDurationMinutes: json['expected_duration_minutes'] as int,
    checkInIntervalMinutes: json['check_in_interval_minutes'] as int?,
    status: JourneyStatus.fromWire(json['status'] as String? ?? 'active'),
    startedAt: DateTime.parse(json['started_at'] as String),
    expectedArrivalAt: DateTime.parse(json['expected_arrival_at'] as String),
    lastCheckInAt: _parseNullableDate(json['last_check_in_at']),
    endedAt: _parseNullableDate(json['ended_at']),
    contactIds: (json['contact_ids'] as List?)?.cast<String>() ?? const [],
  );

  static DateTime? _parseNullableDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  Future<SafeJourney?> getActiveJourney() async {
    final response = await _apiClient.dio.get('$_basePath/active');
    final data = response.data;
    if (data == null || data is! Map<String, dynamic>) return null;
    return _fromJson(data);
  }

  @override
  Future<List<SafeJourney>> listJourneys() async {
    final response = await _apiClient.dio.get(_basePath);
    return (response.data as List).cast<Map<String, dynamic>>().map(_fromJson).toList();
  }

  @override
  Future<SafeJourney> startJourney({
    required String destinationLabel,
    required int expectedDurationMinutes,
    double? destinationLat,
    double? destinationLng,
    int? checkInIntervalMinutes,
    List<String> contactIds = const [],
  }) async {
    final response = await _apiClient.dio.post(
      _basePath,
      data: {
        'destination_label': destinationLabel,
        'expected_duration_minutes': expectedDurationMinutes,
        if (destinationLat != null) 'destination_lat': destinationLat,
        if (destinationLng != null) 'destination_lng': destinationLng,
        if (checkInIntervalMinutes != null) 'check_in_interval_minutes': checkInIntervalMinutes,
        'contact_ids': contactIds,
      },
    );
    return _fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<void> pushLocation({
    required String journeyId,
    required double latitude,
    required double longitude,
    double? accuracyMetres,
  }) async {
    await _apiClient.dio.post(
      '$_basePath/$journeyId/locations',
      data: {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracyMetres != null) 'accuracy_metres': accuracyMetres,
      },
    );
  }

  @override
  Future<List<JourneyBreadcrumb>> getBreadcrumbs(String journeyId) async {
    final response = await _apiClient.dio.get('$_basePath/$journeyId/locations');
    return (response.data as List).cast<Map<String, dynamic>>().map((json) {
      return JourneyBreadcrumb(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyMetres: (json['accuracy_metres'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(json['captured_at'] as String),
      );
    }).toList();
  }

  @override
  Future<SafeJourney> checkIn(String journeyId) => _post('$_basePath/$journeyId/check-in');

  @override
  Future<SafeJourney> markArrived(String journeyId) => _post('$_basePath/$journeyId/arrive');

  @override
  Future<SafeJourney> cancel(String journeyId) => _post('$_basePath/$journeyId/cancel');

  @override
  Future<SafeJourney> escalate(String journeyId) => _post('$_basePath/$journeyId/escalate');

  Future<SafeJourney> _post(String path) async {
    final response = await _apiClient.dio.post(path);
    return _fromJson(response.data as Map<String, dynamic>);
  }
}
