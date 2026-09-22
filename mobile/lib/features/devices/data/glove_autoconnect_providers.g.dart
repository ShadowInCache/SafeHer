// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glove_autoconnect_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$gloveAutoConnectHash() => r'fa38c53dfa7f5c26f69c47348aa416c9dc71fe29';

/// Finds and connects the registered glove with no manual pairing step,
/// so a closed-and-reopened app (or an app that launched before the glove
/// was powered on) resumes streaming on its own.
///
/// **The gap this closes.** [BlePairingController]'s own reconnect only
/// picks up after a connection it already made drops — nothing ever made
/// that first connection in the first place unless the user manually opened
/// the pairing sheet this session, so a fresh app launch (or a launch
/// before the glove had power) had nothing to reconnect, indefinitely.
///
/// This is that missing first step: scan (using [bleServiceProvider]
/// directly, not [BlePairingController]'s own scan — that one drives the
/// pairing sheet's UI state machine, and this runs silently in the
/// background with no sheet open), find a peripheral whose advertised name
/// matches the registered glove's name (the same identity signal
/// [BlePairingController.registerConnectedDevice] already uses to avoid
/// duplicate registrations — the backend record carries no BLE address),
/// then hand the *connect* step to [BlePairingController] itself
/// (`selectDeviceType` + `connect`) rather than calling
/// [BleService.connect] directly. That distinction matters: [GloveLink] —
/// the single owner of the actual classification/telemetry subscription —
/// activates on [BlePairingController]'s stage reaching `connected`, not on
/// [connectedGloveIdProvider] changing. Connecting through [BleService]
/// directly and only setting [connectedGloveIdProvider] by hand would leave
/// the radio link up with [GloveLink] never subscribing — a live "CONNECTED"
/// badge with no data behind it, the exact bug this whole investigation
/// started from, just reached by a different path.
///
/// Bounded and cooperative, not a tight loop: one scan window at a time,
/// with a cooldown between attempts, and it stops entirely the moment
/// [connectedGloveIdProvider] is set by anything (itself, a retry, or the
/// user pairing manually in the meantime) — see [build]'s early return.
/// `keepAlive` so it outlives whatever screen happened to be on top at
/// launch, matching [GloveLink].
///
/// Copied from [GloveAutoConnect].
@ProviderFor(GloveAutoConnect)
final gloveAutoConnectProvider =
    NotifierProvider<GloveAutoConnect, void>.internal(
      GloveAutoConnect.new,
      name: r'gloveAutoConnectProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$gloveAutoConnectHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GloveAutoConnect = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
