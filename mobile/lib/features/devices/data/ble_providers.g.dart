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
    r'f8366534fdcc035261f7dc9b80c350a934ace699';

/// Drives the BLE pairing sheet: permissions → adapter state → live scan →
/// connect + service discovery → backend registration, plus automatic
/// reconnection when a real link drops (including a power cycle — the ESP32
/// losing power and coming back).
///
/// Auto-disposed *with the sheet*, in the Riverpod sense of "nothing left
/// watching or listening" — closing the sheet after a successful pairing
/// does not actually tear this down, because [GloveLink] (`keepAlive`,
/// watched from `main.dart`) holds a `ref.listen` on this provider for the
/// whole app session. That is deliberate and load-bearing: it is what lets
/// the reconnect loop below outlive the sheet at all.
///
/// This controller used to be one of *two* independent things reconnecting
/// a dropped glove — a `GloveConnectionManager` provider called
/// `BleService.connect` directly on its own timer, racing this controller's
/// own reconnect for the same device. Whichever one happened to win left
/// the *other* signal wrong: `GloveConnectionManager` never touched
/// [BlePairingState.stage], so when it won the race the radio came back up
/// but [GloveLink] — which resubscribes on *this* controller reaching
/// [BlePairingStage.connected], not on the raw GATT state — never saw a
/// transition to react to. That reproduced as "shows Connected, no data"
/// after every power cycle, deterministically, because the tighter-interval
/// `GloveConnectionManager` almost always won. `GloveConnectionManager` is
/// gone now; this is the one and only place a reconnect happens.
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
