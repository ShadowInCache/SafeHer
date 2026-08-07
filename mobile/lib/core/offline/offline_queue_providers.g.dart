// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_queue_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$offlineQueueServiceHash() =>
    r'dcecebec765bd047fae0182886e134eb521ece0a';

/// See also [offlineQueueService].
@ProviderFor(offlineQueueService)
final offlineQueueServiceProvider = Provider<OfflineQueueService>.internal(
  offlineQueueService,
  name: r'offlineQueueServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$offlineQueueServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OfflineQueueServiceRef = ProviderRef<OfflineQueueService>;
String _$offlineQueueDrainerHash() =>
    r'aed2b774b1c6ac60bc31b1eeb8ae9b6f59cdfbd8';

/// Watches connectivity and drains the offline queue on every
/// offline→online transition. Read this provider once near the app root
/// (see `SafeHerApp`) purely to keep it alive — it has no UI of its own.
///
/// Copied from [OfflineQueueDrainer].
@ProviderFor(OfflineQueueDrainer)
final offlineQueueDrainerProvider =
    NotifierProvider<OfflineQueueDrainer, void>.internal(
      OfflineQueueDrainer.new,
      name: r'offlineQueueDrainerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$offlineQueueDrainerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$OfflineQueueDrainer = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
