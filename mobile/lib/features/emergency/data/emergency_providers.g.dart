// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emergency_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$emergencyRepositoryHash() =>
    r'2851f3b65166e54e5302a6fc6ed40058bb9db194';

/// See also [emergencyRepository].
@ProviderFor(emergencyRepository)
final emergencyRepositoryProvider =
    AutoDisposeProvider<EmergencyRepository>.internal(
      emergencyRepository,
      name: r'emergencyRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$emergencyRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EmergencyRepositoryRef = AutoDisposeProviderRef<EmergencyRepository>;
String _$emergencyDispatchNotifierHash() =>
    r'25309c4c1b16dee190537c0d2bfd558e16657fc2';

/// Dispatches the SOS alert. If the device is offline when the countdown
/// completes, the alert is queued via [OfflineQueueService] instead of
/// being dropped, and replays automatically the next time connectivity is
/// restored — satisfying "Offline SOS: disable network → trigger →
/// re-enable → alert sent" without blocking the on-screen dispatched
/// confirmation, which still shows immediately either way (the user
/// shouldn't have to wonder whether their SOS "worked" just because
/// they're in a signal dead zone).
///
/// Copied from [EmergencyDispatchNotifier].
@ProviderFor(EmergencyDispatchNotifier)
final emergencyDispatchNotifierProvider =
    NotifierProvider<EmergencyDispatchNotifier, void>.internal(
      EmergencyDispatchNotifier.new,
      name: r'emergencyDispatchNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$emergencyDispatchNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$EmergencyDispatchNotifier = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
