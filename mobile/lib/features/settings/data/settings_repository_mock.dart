import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';

class SettingsRepositoryMock implements SettingsRepository {
  AppSettings _settings = const AppSettings(pushNotifications: true, locationSharing: true, biometricLock: false);

  @override
  Future<AppSettings> getSettings() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _settings;
  }

  @override
  Future<AppSettings> updateSettings(AppSettings settings) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _settings = settings;
    return _settings;
  }
}
