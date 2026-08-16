// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ble_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$bleServiceHash() => r'410f45503c5e666f6dffb5da9180ec255cc717dc';

/// The real radio. Widget tests override this with a fake [BleService] —
/// there is no mock variant behind `AppConfig.useMockApi`, because a fake
/// scan result is exactly the thing this feature exists to stop shipping.
///
/// Copied from [bleService].
@ProviderFor(bleService)
final bleServiceProvider = Provider<BleService>.internal(
  bleService,
  name: r'bleServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$bleServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BleServiceRef = ProviderRef<BleService>;
String _$deviceRegistrationRepositoryHash() =>
    r'03a7b964fc4f32b7624bba80d469f2d25c66d1d5';

/// See also [deviceRegistrationRepository].
@ProviderFor(deviceRegistrationRepository)
final deviceRegistrationRepositoryProvider =
    Provider<DeviceRegistrationRepository>.internal(
      deviceRegistrationRepository,
      name: r'deviceRegistrationRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$deviceRegistrationRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeviceRegistrationRepositoryRef =
    ProviderRef<DeviceRegistrationRepository>;
String _$blePairingControllerHash() =>
    r'9fd055c402319a478f45254937ef20d99a14152b';

/// Drives the BLE pairing sheet: permissions → adapter state → live scan →
/// connect + service discovery → backend registration, plus bounded
/// automatic reconnection when a real link drops.
///
/// Auto-disposed with the sheet. On dispose it cancels its subscriptions
/// and stops any running scan, but deliberately does **not** drop an
/// established GATT link — tearing down a connection the user just made
/// because they swiped a sheet away would be the wrong call. Owning that
/// connection for the rest of the session is a separate concern that
/// belongs to a device-connection manager, which does not exist yet.
///
/// Copied from [BlePairingController].
@ProviderFor(BlePairingController)
final blePairingControllerProvider =
    AutoDisposeNotifierProvider<BlePairingController, BlePairingState>.internal(
      BlePairingController.new,
      name: r'blePairingControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$blePairingControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$BlePairingController = AutoDisposeNotifier<BlePairingState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
