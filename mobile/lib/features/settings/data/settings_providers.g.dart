// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$settingsRepositoryHash() =>
    r'30991fde900e694a441641421ebcbfee7e468e54';

/// See also [settingsRepository].
@ProviderFor(settingsRepository)
final settingsRepositoryProvider =
    AutoDisposeProvider<SettingsRepository>.internal(
      settingsRepository,
      name: r'settingsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$settingsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SettingsRepositoryRef = AutoDisposeProviderRef<SettingsRepository>;
String _$contactsRepositoryHash() =>
    r'ca8ebfb4eacbfbd4d9ad9b3b5d69e3e71c8669c8';

/// See also [contactsRepository].
@ProviderFor(contactsRepository)
final contactsRepositoryProvider =
    AutoDisposeProvider<ContactsRepository>.internal(
      contactsRepository,
      name: r'contactsRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$contactsRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ContactsRepositoryRef = AutoDisposeProviderRef<ContactsRepository>;
String _$appSettingsNotifierHash() =>
    r'87b8af129e25a9aa2575c335c09732a536bbf03c';

/// See also [AppSettingsNotifier].
@ProviderFor(AppSettingsNotifier)
final appSettingsNotifierProvider =
    AutoDisposeAsyncNotifierProvider<AppSettingsNotifier, AppSettings>.internal(
      AppSettingsNotifier.new,
      name: r'appSettingsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$appSettingsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AppSettingsNotifier = AutoDisposeAsyncNotifier<AppSettings>;
String _$managedContactsNotifierHash() =>
    r'a99e236f65d220b0c65ddcf5db968f7a0bb1e523';

/// See also [ManagedContactsNotifier].
@ProviderFor(ManagedContactsNotifier)
final managedContactsNotifierProvider =
    AutoDisposeAsyncNotifierProvider<
      ManagedContactsNotifier,
      List<ManagedContact>
    >.internal(
      ManagedContactsNotifier.new,
      name: r'managedContactsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$managedContactsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ManagedContactsNotifier =
    AutoDisposeAsyncNotifier<List<ManagedContact>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
