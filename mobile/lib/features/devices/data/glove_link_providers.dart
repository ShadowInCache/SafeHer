import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/glove_protocol.dart';
import 'ble_providers.dart';

part 'glove_link_providers.g.dart';

void _bleLog(String message) {
  if (kDebugMode) debugPrint('[BLE] $message');
}

/// What the glove is currently saying.
class GloveLinkState {
  const GloveLinkState({
    this.classification,
    this.telemetry,
    this.isListening = false,
    this.telemetryUnsupported = false,
    this.heartRateBpm,
    this.heartRateUnsupported = false,
    this.lastUpdate,
  });

  /// The most recent classification from the on-device model, if any.
  final GloveClassification? classification;

  /// The most recent telemetry tick, if any.
  final GloveTelemetry? telemetry;

  /// The glove's latest valid heart rate in beats per minute, or null when it
  /// has none -- no finger, weak signal, no recent beat, or firmware without a
  /// pulse sensor. Never zero. Cleared the moment the link drops, so a stale
  /// reading cannot outlive the connection that produced it.
  ///
  /// Student prototype: an optical estimate, not medically accurate.
  final int? heartRateBpm;

  /// The glove connected but has no heart-rate characteristic -- firmware
  /// without the pulse sensor. Lets the UI say so instead of showing a blank
  /// that looks like a fault.
  final bool heartRateUnsupported;

  /// Subscribed to at least the classification characteristic.
  final bool isListening;

  /// The glove connected but has no telemetry characteristic -- firmware
  /// older than the one that added it. Surfaced rather than swallowed so the
  /// UI can say "this glove reports classifications only" instead of showing
  /// blank readings that look like a bug.
  final bool telemetryUnsupported;

  final DateTime? lastUpdate;

  bool get hasData => classification != null || telemetry != null || heartRateBpm != null;

  /// [clearHeartRate] exists because the null-coalescing merge below cannot
  /// express "set the heart rate back to none": the glove saying `BPM,NONE`
  /// has to erase the last reading, not leave it on screen.
  GloveLinkState copyWith({
    GloveClassification? classification,
    GloveTelemetry? telemetry,
    bool? isListening,
    bool? telemetryUnsupported,
    int? heartRateBpm,
    bool clearHeartRate = false,
    bool? heartRateUnsupported,
    DateTime? lastUpdate,
  }) {
    return GloveLinkState(
      classification: classification ?? this.classification,
      telemetry: telemetry ?? this.telemetry,
      isListening: isListening ?? this.isListening,
      telemetryUnsupported: telemetryUnsupported ?? this.telemetryUnsupported,
      heartRateBpm: clearHeartRate ? null : (heartRateBpm ?? this.heartRateBpm),
      heartRateUnsupported: heartRateUnsupported ?? this.heartRateUnsupported,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }
}

/// Listens to a connected SafeHer glove and holds what it reports.
///
/// **The gap this closes.** Pairing worked and the model ran on the ESP32,
/// but nothing in the app ever subscribed to a characteristic -- so the glove
/// notified its classifications into a socket with no listener, and the
/// device card showed hardcoded zeros beside a device that was genuinely
/// connected.
///
/// Subscription follows the pairing stage rather than being started by hand:
/// a link that drops and is re-established has to resubscribe, and leaving
/// that to a caller is how it ends up done in one place and forgotten in
/// another.
///
/// `keepAlive` because the glove is not tied to a screen. It keeps reporting
/// while the user is on Home, in Settings, or has the app in the background,
/// and a link torn down by navigation would be a safety device that only
/// works while you are looking at it.
@Riverpod(keepAlive: true)
class GloveLink extends _$GloveLink {
  StreamSubscription<String>? _classificationSub;
  StreamSubscription<String>? _telemetrySub;
  StreamSubscription<String>? _heartRateSub;
  String? _listeningTo;
  bool _gotFirstClassification = false;
  bool _heartRateAvailable = false;

  @override
  GloveLinkState build() {
    ref.listen(blePairingControllerProvider, (previous, next) {
      // `registered` must count: registration finishing is not a link drop,
      // and treating it as one cancelled the live subscription right after
      // pairing, leaving "Connected" with no data.
      final connected = next.holdsConnection;
      final deviceId = next.target?.id;
      _bleLog(
        'pairing state changed: ${previous?.stage} -> ${next.stage} '
        '(deviceId=$deviceId, listeningTo=$_listeningTo)',
      );

      if (!connected || deviceId == null) {
        if (_listeningTo != null) _bleLog('disconnected');
        _stop();
        return;
      }
      if (_listeningTo == deviceId) return;
      unawaited(_listen(deviceId, next.target?.advertisedName));
    });

    ref.onDispose(_stop);
    return const GloveLinkState();
  }

  Future<void> _listen(String deviceId, String? advertisedName) async {
    _cancelSubscriptions();
    _listeningTo = deviceId;
    _gotFirstClassification = false;
    _heartRateAvailable = false;

    // Only SafeHer gloves speak this protocol. Subscribing to a stranger's
    // peripheral would either throw or feed nonsense into the threat display.
    if (advertisedName != null &&
        advertisedName.isNotEmpty &&
        !advertisedName.toLowerCase().contains('safeher')) {
      state = const GloveLinkState();
      return;
    }

    final service = ref.read(bleServiceProvider);

    // Classification is the characteristic that matters; a glove that cannot
    // provide it is not usable as a sensor, so a failure here clears the
    // state rather than leaving a stale reading on screen.
    _bleLog('notification subscription started ($deviceId)');
    try {
      _classificationSub = service
          .subscribeToCharacteristic(
            deviceId,
            serviceUuid: GloveBle.serviceUuid,
            characteristicUuid: GloveBle.classificationCharacteristicUuid,
          )
          .listen(_onClassification, onError: (error) {
            _bleLog('classification subscription error: $error');
            _stop();
          });
      state = state.copyWith(isListening: true);
      // Note the error is handled in `onError` above as well as here.
      // `subscribeToCharacteristic` is an `async*` generator, so a missing
      // characteristic throws when the stream is *listened to*, not when the
      // method is called -- a try/catch around `.listen()` alone never fires.
    } on Object catch (error) {
      _bleLog('failed to subscribe to classification characteristic: $error');
      _listeningTo = null;
      state = const GloveLinkState();
      return;
    }

    // Telemetry is optional: firmware predating it simply has no such
    // characteristic. That is a capability difference, not a fault, so the
    // classification stream stays up and the UI is told why the numbers are
    // missing.
    try {
      _telemetrySub = service
          .subscribeToCharacteristic(
            deviceId,
            serviceUuid: GloveBle.serviceUuid,
            characteristicUuid: GloveBle.telemetryCharacteristicUuid,
          )
          .listen(
            _onTelemetry,
            // Same reason as above: this is where a glove without the
            // telemetry characteristic actually surfaces. Swallowing it here
            // left `telemetryUnsupported` false and the UI unable to say why
            // the readings were blank.
            onError: (_) => state = state.copyWith(telemetryUnsupported: true),
          );
    } on Object {
      state = state.copyWith(telemetryUnsupported: true);
    }

    // Heart rate is optional in the same way: a glove without the pulse sensor
    // (or older firmware) has no such characteristic, which must not disturb
    // the classification stream. Same single-subscription rule as the other
    // two -- this is the only place that ever subscribes to it, and
    // `_cancelSubscriptions` drops it together with them on every disconnect,
    // so a reconnect starts a fresh one and never a second.
    try {
      _heartRateSub = service
          .subscribeToCharacteristic(
            deviceId,
            serviceUuid: GloveBle.serviceUuid,
            characteristicUuid: GloveBle.heartRateCharacteristicUuid,
          )
          .listen(
            _onHeartRate,
            onError: (error) {
              _bleLog('heart rate characteristic unavailable: $error');
              state = state.copyWith(heartRateUnsupported: true);
            },
          );
    } on Object {
      state = state.copyWith(heartRateUnsupported: true);
    }
  }

  void _onHeartRate(String raw) {
    final parsed = GloveHeartRate.tryParse(raw);
    // Garbled packet: keep what is on screen, like the other characteristics.
    if (parsed == null) return;

    final bpm = parsed.bpm;
    final available = bpm != null;
    // Log on availability changes only -- this ticks once a second.
    if (available != _heartRateAvailable) {
      _heartRateAvailable = available;
      _bleLog(available ? 'heart rate available ($bpm bpm)' : 'heart rate unavailable (no valid reading)');
    }
    state = bpm == null
        ? state.copyWith(clearHeartRate: true, lastUpdate: DateTime.now())
        : state.copyWith(heartRateBpm: bpm, lastUpdate: DateTime.now());
  }

  void _onClassification(String raw) {
    final parsed = GloveClassification.tryParse(raw);
    // Unparsable notifications are dropped rather than clearing what is on
    // screen: a truncated packet is a lost reading, not evidence that the
    // last real one was wrong.
    if (parsed == null) return;
    if (!_gotFirstClassification) {
      _gotFirstClassification = true;
      _bleLog('first notification received (${parsed.label}, ${parsed.confidence})');
    } else {
      _bleLog('notification received (${parsed.label}, ${parsed.confidence})');
    }
    state = state.copyWith(classification: parsed, lastUpdate: DateTime.now());
  }

  void _onTelemetry(String raw) {
    final parsed = GloveTelemetry.tryParse(raw);
    if (parsed == null) return;
    state = state.copyWith(telemetry: parsed, lastUpdate: DateTime.now());
  }

  /// Drops the old subscriptions without awaiting their cancellation.
  ///
  /// THE ROOT CAUSE of "reconnect shows Connected but no data": the old
  /// subscription is on `subscribeToCharacteristic`'s `async*` generator,
  /// and its `.cancel()` only resolves once that generator's own `finally`
  /// block finishes — which, live on-device, was never observed to happen
  /// at all when the peripheral had already disconnected (confirmed by
  /// logging every step: the generator's cleanup log never printed, even
  /// tens of seconds later). Awaiting that cancel() here, as this used to,
  /// permanently blocked `_listen` on a cleanup from the *previous*
  /// connection that would never complete — nulling `_listeningTo` never
  /// advanced, so no reconnect ever resubscribed. An app restart "fixed" it
  /// only because a fresh `GloveLink` has no stuck subscription to wait on.
  ///
  /// This mirrors `BlePairingController._cancelScanSubscriptions`'s own
  /// documented reasoning for the same non-awaited pattern: a third-party
  /// SDK's stream must never be given the power to wedge this flow. Fields
  /// are cleared *immediately* (not after the cancel resolves) specifically
  /// so a stray, still-pending old cancel() cannot later null out a
  /// brand-new subscription that has since replaced it.
  void _cancelSubscriptions() {
    final classificationSub = _classificationSub;
    final telemetrySub = _telemetrySub;
    final heartRateSub = _heartRateSub;
    _classificationSub = null;
    _telemetrySub = null;
    _heartRateSub = null;
    unawaited(classificationSub?.cancel());
    unawaited(telemetrySub?.cancel());
    unawaited(heartRateSub?.cancel());
  }

  void _stop() {
    _cancelSubscriptions();
    _listeningTo = null;
    if (state.hasData || state.isListening) state = const GloveLinkState();
  }
}
