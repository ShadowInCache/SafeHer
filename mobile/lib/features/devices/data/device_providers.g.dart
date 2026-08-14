// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$deviceRepositoryHash() => r'c3cb4a6ce61fd84427d0887b4bd597f35b6843f1';

/// See also [deviceRepository].
@ProviderFor(deviceRepository)
final deviceRepositoryProvider = AutoDisposeProvider<DeviceRepository>.internal(
  deviceRepository,
  name: r'deviceRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$deviceRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DeviceRepositoryRef = AutoDisposeProviderRef<DeviceRepository>;
String _$devicesHash() => r'177fe56e20fdef5608366d9d6919478330b1e13e';

/// See also [devices].
@ProviderFor(devices)
final devicesProvider = AutoDisposeFutureProvider<List<DeviceDetail>>.internal(
  devices,
  name: r'devicesProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$devicesHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DevicesRef = AutoDisposeFutureProviderRef<List<DeviceDetail>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
