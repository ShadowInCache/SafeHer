// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$connectivityNotifierHash() =>
    r'd686ed3aba2e824097130001cce929bd4b90361c';

/// Whether the device currently has *some* network interface up
/// (Wi-Fi/mobile/ethernet). This is reachability of a network, not proof
/// the SafeHer backend itself is reachable — [ApiException] still handles
/// the "online but the server rejected/timed out" case separately.
///
/// Copied from [ConnectivityNotifier].
@ProviderFor(ConnectivityNotifier)
final connectivityNotifierProvider =
    AutoDisposeStreamNotifierProvider<ConnectivityNotifier, bool>.internal(
      ConnectivityNotifier.new,
      name: r'connectivityNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$connectivityNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ConnectivityNotifier = AutoDisposeStreamNotifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
