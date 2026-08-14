import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';
import 'settings_repository_mock.dart';
import 'settings_repository_remote.dart';

part 'settings_providers.g.dart';

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  if (AppConfig.useMockApi) return SettingsRepositoryMock();
  return SettingsRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
class AppSettingsNotifier extends _$AppSettingsNotifier {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).getSettings();
  }

  Future<void> setPushNotifications(bool value) => _update((s) => s.copyWith(pushNotifications: value));

  Future<void> setSmsNotifications(bool value) => _update((s) => s.copyWith(smsNotifications: value));

  Future<void> setEmailNotifications(bool value) => _update((s) => s.copyWith(emailNotifications: value));

  Future<void> setLocationSharing(bool value) => _update((s) => s.copyWith(locationSharing: value));

  Future<void> _update(AppSettings Function(AppSettings) transform) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = transform(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).updateSettings(next);
  }
}
