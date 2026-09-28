import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/ble_service.dart';
import '../domain/models/ble_models.dart';
import '../domain/models/ble_pairing_state.dart';
import '../domain/models/device_detail.dart';
import 'ble_providers.dart';
import 'device_providers.dart';

part 'glove_autoconnect_providers.g.dart';

void _bleLog(String message) {
  if (kDebugMode) debugPrint('[BLE] $message');
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

/// How long one scan window waits for the registered glove to show up
/// before giving up for this attempt. `@visibleForTesting` so tests do not
/// have to wait 12 real seconds per attempt.
@visibleForTesting
Duration gloveAutoConnectScanWindow = const Duration(seconds: 12);

/// How long to wait after a failed attempt before trying again.
/// `@visibleForTesting` for the same reason as [gloveAutoConnectScanWindow].
@visibleForTesting
Duration gloveAutoConnectCooldown = const Duration(seconds: 8);

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
@Riverpod(keepAlive: true)
class GloveAutoConnect extends _$GloveAutoConnect {
  Timer? _cooldownTimer;
  StreamSubscription<List<BleDiscoveredDevice>>? _scanSub;
  bool _attemptInFlight = false;
  int _generation = 0;

  /// Cached so [build]'s `onDispose` can stop a running scan without
  /// calling `ref.read` during teardown, which throws once the container
  /// has started disposing providers — the same reasoning as
  /// [BlePairingController._cachedService].
  BleService? _cachedService;

  /// True once this provider has been disposed. [_generation] alone is not
  /// enough to guard against a disposed provider: it is only bumped by
  /// [build] rerunning, but disposal (this provider being torn down without
  /// a rebuild — e.g. the whole `ProviderContainer` going away) does not
  /// rerun [build]. An [_attempt] suspended on the scan-window timeout would
  /// otherwise resume after disposal, see its old generation still current,
  /// and call `ref.read` on a container that no longer accepts it.
  bool _disposed = false;

  @override
  void build() {
    final myGeneration = ++_generation;
    final service = ref.read(bleServiceProvider);
    _cachedService = service;
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _cooldownTimer?.cancel();
      _cooldownTimer = null;
      unawaited(_scanSub?.cancel());
      _scanSub = null;
      if (_attemptInFlight) unawaited(_cachedService?.stopScan().catchError((_) {}));
    });

    // Already have a glove — nothing for this provider to do. Covers both
    // "already connected" and "a manual pairing is in flight right now".
    if (ref.read(connectedGloveIdProvider) != null) return;
    if (_attemptInFlight) return;

    unawaited(_attempt(myGeneration));
  }

  Future<void> _attempt(int generation) async {
    _attemptInFlight = true;
    try {
      List<DeviceDetail> devices;
      try {
        devices = await ref.read(devicesProvider.future);
      } catch (_) {
        // Can't reach the backend right now — try again after the cooldown
        // rather than giving up for the rest of the app session.
        _scheduleRetry(generation);
        return;
      }
      if (generation != _generation) return; // superseded while awaiting

      final glove = _firstWhereOrNull(devices, (d) => d.type == DeviceType.glove);
      if (glove == null) {
        // No glove registered on this account at all — nothing to look for.
        // If one gets registered later this session (first-time pairing),
        // that pairing sets connectedGloveIdProvider itself; this provider
        // does not need to keep polling for a device that does not exist.
        return;
      }

      _bleLog('auto-connect: looking for registered glove "${glove.name}"');
      final service = ref.read(bleServiceProvider);
      try {
        await service.startScan(timeout: gloveAutoConnectScanWindow);
      } on BleFailure catch (failure) {
        _bleLog('auto-connect: scan failed to start (${failure.message}), will retry');
        _scheduleRetry(generation);
        return;
      }
      if (generation != _generation) {
        unawaited(service.stopScan());
        return;
      }

      final completer = Completer<BleDiscoveredDevice?>();
      _scanSub = service.scanResults.listen((found) {
        if (completer.isCompleted) return;
        final match = _firstWhereOrNull(found, (d) => d.advertisedName.trim() == glove.name);
        if (match != null) completer.complete(match);
      });

      final match = await completer.future.timeout(gloveAutoConnectScanWindow, onTimeout: () => null);
      unawaited(_scanSub?.cancel());
      _scanSub = null;
      unawaited(service.stopScan());

      if (generation != _generation) return;
      if (match == null) {
        _bleLog('auto-connect: glove not found this window, will retry');
        _scheduleRetry(generation);
        return;
      }
      if (ref.read(connectedGloveIdProvider) != null) return; // beaten by a manual pairing meanwhile

      // BlePairingController is a single shared instance (the pairing sheet
      // uses the same one this reaches for below). If a manual pairing
      // attempt is already mid-flight here — started after this attempt's
      // own scan began, so connectedGloveIdProvider isn't set yet either —
      // calling connect() now would race it. Back off and let whichever one
      // is already running finish; BlePairingController.connect() also
      // guards this itself as a second line of defense, but checking here
      // first avoids burning a retry window on an attempt that would just
      // be ignored.
      final pairingState = ref.read(blePairingControllerProvider);
      if (pairingState.isBusy || pairingState.holdsConnection) {
        _bleLog('auto-connect: pairing controller busy (${pairingState.stage}), will retry');
        _scheduleRetry(generation);
        return;
      }

      _bleLog('auto-connect: found "${match.advertisedName}", connecting');
      // Routed through BlePairingController, not BleService directly: this
      // is what makes GloveLink's stage-based subscription trigger fire
      // (see the class doc for why connecting any other way leaves the
      // link up with no subscription behind it).
      final pairing = ref.read(blePairingControllerProvider.notifier);
      pairing.selectDeviceType(DeviceType.glove);
      try {
        await pairing.connect(match);
      } on Object catch (error) {
        // BlePairingController.connect() catches its own failures into
        // state rather than rethrowing, but guard anyway in case that
        // changes — a thrown error here must not kill this provider.
        _bleLog('auto-connect: connect failed ($error), will retry');
        _scheduleRetry(generation);
        return;
      }
      if (generation != _generation) return;
      if (ref.read(blePairingControllerProvider).stage != BlePairingStage.connected) {
        _bleLog('auto-connect: connect did not reach "connected", will retry');
        _scheduleRetry(generation);
        return;
      }

      _bleLog('auto-connect: connected, GloveLink now owns the subscription');
      // BlePairingController.connect() already calls _syncConnectedGloveId()
      // on success, which sets connectedGloveIdProvider itself (since we
      // just called selectDeviceType(glove)) — nothing left to set by hand.
      // From here, GloveLink (subscription) and BlePairingController's own
      // reconnect-on-drop take over exactly as they would for a manual
      // pairing — this provider's job for this app session is done.
    } finally {
      _attemptInFlight = false;
    }
  }

  void _scheduleRetry(int generation) {
    if (_disposed) return;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(gloveAutoConnectCooldown, () {
      if (_disposed || generation != _generation) return;
      if (ref.read(connectedGloveIdProvider) != null) return;
      unawaited(_attempt(generation));
    });
  }
}
