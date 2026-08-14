import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/models/nearby_place.dart';
import '../domain/models/safety_settings.dart';
import '../domain/safety_repository.dart';

/// `fastapi_app`-backed [SafetyRepository] — `/api/v1/safety/*`.
class SafetyRepositoryRemote implements SafetyRepository {
  SafetyRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  SafetyPreferences _preferencesFromJson(Map<String, dynamic> json) => SafetyPreferences(
    shakeTriggerEnabled: json['shake_trigger_enabled'] as bool? ?? false,
    shakeSensitivity: json['shake_sensitivity'] as int? ?? 2,
    voiceCommandsEnabled: json['voice_commands_enabled'] as bool? ?? false,
    requirePinToCancel: json['require_pin_to_cancel'] as bool? ?? false,
    journeyAutoShareLocation: json['journey_auto_share_location'] as bool? ?? true,
  );

  @override
  Future<SafetyPreferences> getPreferences() async {
    final response = await _apiClient.dio.get('/safety/preferences');
    return _preferencesFromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<SafetyPreferences> updatePreferences(SafetyPreferences preferences) async {
    final response = await _apiClient.dio.patch(
      '/safety/preferences',
      data: {
        'shake_trigger_enabled': preferences.shakeTriggerEnabled,
        'shake_sensitivity': preferences.shakeSensitivity,
        'voice_commands_enabled': preferences.voiceCommandsEnabled,
        'require_pin_to_cancel': preferences.requirePinToCancel,
        'journey_auto_share_location': preferences.journeyAutoShareLocation,
      },
    );
    return _preferencesFromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<SafetyPinStatus> getPinStatus() async {
    final response = await _apiClient.dio.get('/safety/pin');
    final json = response.data as Map<String, dynamic>;
    final lockedUntil = json['locked_until'] as String?;
    return SafetyPinStatus(
      isSet: json['is_set'] as bool? ?? false,
      isLocked: json['is_locked'] as bool? ?? false,
      lockedUntil: lockedUntil == null ? null : DateTime.tryParse(lockedUntil),
    );
  }

  @override
  Future<void> setPin({required String pin, String? currentPin}) async {
    await _apiClient.dio.put(
      '/safety/pin',
      data: {'pin': pin, if (currentPin != null) 'current_pin': currentPin},
    );
  }

  @override
  Future<void> removePin(String pin) async {
    await _apiClient.dio.delete('/safety/pin', data: {'pin': pin});
  }

  @override
  Future<PinVerificationResult> verifyPin(String pin) async {
    final response = await _apiClient.dio.post('/safety/pin/verify', data: {'pin': pin});
    final json = response.data as Map<String, dynamic>;
    final lockedUntil = json['locked_until'] as String?;
    return PinVerificationResult(
      valid: json['valid'] as bool? ?? false,
      attemptsRemaining: json['attempts_remaining'] as int?,
      lockedUntil: lockedUntil == null ? null : DateTime.tryParse(lockedUntil),
    );
  }

  @override
  Future<List<NearbyPlace>> findNearby({
    required double latitude,
    required double longitude,
    int radiusMetres = 3000,
    List<NearbyPlaceCategory>? categories,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/safety/nearby',
        queryParameters: {
          'latitude': latitude,
          'longitude': longitude,
          'radius_metres': radiusMetres,
          if (categories != null && categories.isNotEmpty)
            'categories': categories.map((c) => c.wireValue).toList(),
        },
      );
      return (response.data as List)
          .cast<Map<String, dynamic>>()
          .map(_placeFromJson)
          .whereType<NearbyPlace>()
          .toList();
    } on DioException catch (error) {
      if (error.response?.statusCode == 429) {
        throw const NearbyRateLimitedException();
      }
      rethrow;
    }
  }

  NearbyPlace? _placeFromJson(Map<String, dynamic> json) {
    final category = NearbyPlaceCategory.fromWire(json['category'] as String? ?? '');
    if (category == null) return null;
    return NearbyPlace(
      id: json['id'] as String,
      name: json['name'] as String,
      category: category,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      distanceMetres: json['distance_metres'] as int,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      openHours: json['open_hours'] as String?,
    );
  }
}
