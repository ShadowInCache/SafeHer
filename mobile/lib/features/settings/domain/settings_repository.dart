import 'models/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> getSettings();
  Future<AppSettings> updateSettings(AppSettings settings);
}
