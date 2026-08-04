import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/contacts_repository.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/managed_contact.dart';
import '../domain/settings_repository.dart';
import 'contacts_repository_mock.dart';
import 'settings_repository_mock.dart';

part 'settings_providers.g.dart';

@riverpod
SettingsRepository settingsRepository(Ref ref) {
  return SettingsRepositoryMock();
}

@riverpod
ContactsRepository contactsRepository(Ref ref) {
  return ContactsRepositoryMock();
}

@riverpod
class AppSettingsNotifier extends _$AppSettingsNotifier {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).getSettings();
  }

  Future<void> setPushNotifications(bool value) => _update((s) => s.copyWith(pushNotifications: value));

  Future<void> setLocationSharing(bool value) => _update((s) => s.copyWith(locationSharing: value));

  Future<void> setBiometricLock(bool value) => _update((s) => s.copyWith(biometricLock: value));

  Future<void> _update(AppSettings Function(AppSettings) transform) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = transform(current);
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).updateSettings(next);
  }
}

@riverpod
class ManagedContactsNotifier extends _$ManagedContactsNotifier {
  @override
  Future<List<ManagedContact>> build() {
    return ref.watch(contactsRepositoryProvider).getContacts();
  }

  Future<void> addContact(String name, String relationship) async {
    state = AsyncData(await ref.read(contactsRepositoryProvider).addContact(name, relationship));
  }

  Future<void> removeContact(String id) async {
    state = AsyncData(await ref.read(contactsRepositoryProvider).removeContact(id));
  }

  Future<void> reorder(List<ManagedContact> newOrder) async {
    state = AsyncData(newOrder);
    await ref.read(contactsRepositoryProvider).reorderContacts(newOrder);
  }
}
