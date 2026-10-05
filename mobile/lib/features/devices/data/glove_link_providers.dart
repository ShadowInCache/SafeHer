import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/glove_protocol.dart';
import 'ble_providers.dart';

part 'glove_link_providers.g.dart';

void _bleLog(String message) {
  if (kDebugMode) debugPrint('[BLE] $message');
}

/// How long the glove may stay silent before it counts as not reporting.
///
/// It classifies a 100-sample window every ~0.5 s and notifies every result,
/// `NORMAL` included, so silence is never normal. Fifteen seconds is thirty
/// missed windows: unambiguous, while still tolerating a few dropped BLE
/// notifications and a slow reconnect.
///
/// Mutable and `@visibleForTesting` for the same reason
/// `gloveAutoConnectScanWindow` is: a test should not have to wait fifteen
/// real seconds to prove the glove went quiet.
@visibleForTesting
Duration gloveSilenceTimeout = const Duration(seconds: 15);

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
    this.isReporting = false,
    this.droppedNotifications = 0,
  });

  /// How long the glove may stay silent before it counts as not reporting.
  static Duration get silenceTimeout => gloveSilenceTimeout;

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
  ///
  /// **Subscribed is not the same as hearing anything.** A glove whose sensor
  /// failed at boot still advertises, still pairs, and still accepts a
  /// subscription — it simply never notifies. See [isReporting].
  final bool isListening;

  /// Whether a classification has actually arrived recently.
  ///
  /// **The gap this closes.** [isListening] only says a BLE subscription
  /// exists, and the UI drew "Your glove is watching" from it. But the
  /// firmware checks the IMU *after* starting BLE, so a glove with a dead
  /// MPU-6500 pairs, reports connected, halts in an infinite loop, and sends
  /// nothing — and the app said it was watching. The same silence follows a
  /// wedged inference loop, a flat battery, or a glove left in
  /// `DATA_COLLECTION_MODE 1`.
  ///
  /// The fused score was already honest about this: the aggregator drops a
  /// reading older than ten seconds, so the signal went absent on its own.
  /// Only the UI was claiming protection that had stopped. This is the value
  /// screens should believe.
  final bool isReporting;

  /// True when the link is up but nothing is coming over it.
  bool get isSilent => isListening && !isReporting;

  /// How many classifications were lost in transit on this connection.
  ///
  /// Counted from gaps in the firmware's inference counter, so it is only ever
  /// non-zero against firmware that sends one. **Zero therefore means either
  /// "none lost" or "this glove cannot tell us"** — [lossIsMeasurable]
  /// separates the two, and no caller should read a zero as proof of a clean
  /// link without checking it.
  ///
  /// Why it matters: GATT notifications are unacknowledged, a fall produces
  /// two to four windows, and the alarm rule needs two of them. Losing two of
  /// three costs an alarm, and before this there was no way to know it had
  /// happened.
  final int droppedNotifications;

  /// Whether this glove's firmware reports an inference counter at all.
  bool get lossIsMeasurable => classification?.sequence != null;

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
    bool? isReporting,
    int? droppedNotifications,
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
      isReporting: isReporting ?? this.isReporting,
      droppedNotifications: droppedNotifications ?? this.droppedNotifications,
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
  /// Flips [GloveLinkState.isReporting] off when the glove goes quiet.
  ///
  /// A timer rather than a computed getter because nothing redraws on its own
  /// when *no* event arrives: silence produces no state change to react to,
  /// which is exactly why it went unnoticed.
  Timer? _silenceWatchdog;

  /// The last inference counter seen, for spotting gaps. Null until a glove
  /// that sends one has been heard from.
  int? _lastSequence;

  /// Lost classifications on this connection. Reset with the link, not kept
  /// across reconnects: the firmware's counter restarts when it reboots, and
  /// carrying a total over that boundary would describe two different runs.
  int _dropped = 0;

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

  /// Restarts the silence watchdog. Called on every classification.
  void _markReporting() {
    _silenceWatchdog?.cancel();
    _silenceWatchdog = Timer(GloveLinkState.silenceTimeout, () {
      if (!state.isListening) return;
      _bleLog('glove silent for ${GloveLinkState.silenceTimeout.inSeconds}s '
          '— reporting stopped');
      state = state.copyWith(isReporting: false);
    });
  }

  /// Counts classifications lost between [previous] and [next].
  ///
  /// A counter that goes backwards or stands still is a glove that rebooted
  /// (it restarts at zero), not four billion lost packets, so tracking
  /// restarts rather than reporting an absurd gap. Same treatment covers a
  /// uint32 wrap, which at two inferences a second is about sixty-eight years
  /// away and still should not produce nonsense if it ever arrives.
  int _gapBetween(int previous, int next) {
    final delta = next - previous;
    if (delta <= 0) {
      _bleLog('sequence restarted ($previous -> $next); loss count reset');
      return 0;
    }
    return delta - 1;
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
    final sequence = parsed.sequence;
    if (sequence != null) {
      final previous = _lastSequence;
      if (previous != null) {
        final lost = _gapBetween(previous, sequence);
        if (lost > 0) {
          _dropped += lost;
          // Logged rather than surfaced as an alarm: losing a notification is
          // not itself an emergency, and the next window is already on its
          // way. It is recorded so a bench session can see whether the link
          // is healthy, which was previously unknowable.
          _bleLog('lost $lost notification(s) before #$sequence '
              '($_dropped on this connection)');
        }
        if (lost < 0 || sequence <= previous) _dropped = 0;
      }
      _lastSequence = sequence;
    }

    state = state.copyWith(
      classification: parsed,
      lastUpdate: DateTime.now(),
      isReporting: true,
      droppedNotifications: _dropped,
    );
    _markReporting();
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
    // Cancelled with the subscriptions: a watchdog left running past a
    // disconnect would fire into a disposed notifier, and there is nothing
    // left for it to report on anyway.
    _silenceWatchdog?.cancel();
    _silenceWatchdog = null;
    // The firmware's counter restarts when it reboots, so carrying either of
    // these across a reconnect would compare two different runs and invent a
    // gap that never happened.
    _lastSequence = null;
    _dropped = 0;
    _listeningTo = null;
    if (state.hasData || state.isListening) state = const GloveLinkState();
  }
}
