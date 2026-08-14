import '../../../core/network/api_client.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';

/// `fastapi_app`-backed [SettingsRepository] — `GET`/`PATCH /api/v1/users/me`.
/// Notification/location-sharing preferences live as real columns on the
/// same `User` row every other screen reads (see
/// `fastapi_app/models.py`) — not a separate Firestore document nobody
/// else's data agrees with.
class SettingsRepositoryRemote implements SettingsRepository {
  SettingsRepositoryRemote({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  AppSettings _fromJson(Map<String, dynamic> json) => AppSettings(
    pushNotifications: json['push_notifications'] as bool? ?? true,
    smsNotifications: json['sms_notifications'] as bool? ?? false,
    emailNotifications: json['email_notifications'] as bool? ?? true,
    locationSharing: json['location_sharing'] as bool? ?? true,
  );

  @override
  Future<AppSettings> getSettings() async {
    final response = await _apiClient.dio.get('/users/me');
    return _fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<AppSettings> updateSettings(AppSettings settings) async {
    final response = await _apiClient.dio.patch(
      '/users/me',
      data: {
        'push_notifications': settings.pushNotifications,
        'sms_notifications': settings.smsNotifications,
        'email_notifications': settings.emailNotifications,
        'location_sharing': settings.locationSharing,
      },
    );
    return _fromJson(response.data as Map<String, dynamic>);
  }
}
