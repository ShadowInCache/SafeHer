import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/glove_protocol.dart';
import '../domain/models/ble_pairing_state.dart';
import 'ble_providers.dart';

part 'glove_link_providers.g.dart';

/// What the glove is currently saying.
class GloveLinkState {
  const GloveLinkState({
    this.classification,
    this.telemetry,
    this.isListening = false,
    this.telemetryUnsupported = false,
    this.lastUpdate,
  });

  /// The most recent classification from the on-device model, if any.
  final GloveClassification? classification;

  /// The most recent telemetry tick, if any.
  final GloveTelemetry? telemetry;

  /// Subscribed to at least the classification characteristic.
  final bool isListening;

  /// The glove connected but has no telemetry characteristic -- firmware
  /// older than the one that added it. Surfaced rather than swallowed so the
  /// UI can say "this glove reports classifications only" instead of showing
  /// blank readings that look like a bug.
  final bool telemetryUnsupported;

  final DateTime? lastUpdate;

  bool get hasData => classification != null || telemetry != null;

  GloveLinkState copyWith({
    GloveClassification? classification,
    GloveTelemetry? telemetry,
    bool? isListening,
    bool? telemetryUnsupported,
    DateTime? lastUpdate,
  }) {
    return GloveLinkState(
      classification: classification ?? this.classification,
      telemetry: telemetry ?? this.telemetry,
      isListening: isListening ?? this.isListening,
      telemetryUnsupported: telemetryUnsupported ?? this.telemetryUnsupported,
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
  String? _listeningTo;

  @override
  GloveLinkState build() {
    ref.listen(blePairingControllerProvider, (previous, next) {
      final connected = next.stage == BlePairingStage.connected ||
          next.stage == BlePairingStage.registering;
      final deviceId = next.target?.id;

      if (!connected || deviceId == null) {
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
    await _cancelSubscriptions();
    _listeningTo = deviceId;

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
    try {
      _classificationSub = service
          .subscribeToCharacteristic(
            deviceId,
            serviceUuid: GloveBle.serviceUuid,
            characteristicUuid: GloveBle.classificationCharacteristicUuid,
          )
          .listen(_onClassification, onError: (_) => _stop());
      state = state.copyWith(isListening: true);
      // Note the error is handled in `onError` above as well as here.
      // `subscribeToCharacteristic` is an `async*` generator, so a missing
      // characteristic throws when the stream is *listened to*, not when the
      // method is called -- a try/catch around `.listen()` alone never fires.
    } on Object {
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
  }

  void _onClassification(String raw) {
    final parsed = GloveClassification.tryParse(raw);
    // Unparsable notifications are dropped rather than clearing what is on
    // screen: a truncated packet is a lost reading, not evidence that the
    // last real one was wrong.
    if (parsed == null) return;
    state = state.copyWith(classification: parsed, lastUpdate: DateTime.now());
  }

  void _onTelemetry(String raw) {
    final parsed = GloveTelemetry.tryParse(raw);
    if (parsed == null) return;
    state = state.copyWith(telemetry: parsed, lastUpdate: DateTime.now());
  }

  Future<void> _cancelSubscriptions() async {
    await _classificationSub?.cancel();
    await _telemetrySub?.cancel();
    _classificationSub = null;
    _telemetrySub = null;
  }

  void _stop() {
    unawaited(_cancelSubscriptions());
    _listeningTo = null;
    if (state.hasData || state.isListening) state = const GloveLinkState();
  }
}
