import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/ble_models.dart';
import '../domain/models/motion_data.dart';
import '../domain/models/motion_risk_score.dart';
import 'ble_providers.dart';

/// GATT UUIDs for the SafeHer glove's on-device motion classifier,
/// exactly as advertised by
/// `glove/firmware/SafeHer_Glove_Final/SafeHer_Glove_Final.ino`. This is
/// the SAME service `BlePairingController` already connects to and
/// discovers during pairing (see `ble_service.dart`'s class doc) — no
/// second BLE service is created here.
const kGloveMotionServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const kGloveMotionCharacteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

/// Live [MotionData] for a glove this app already holds a GATT connection
/// to, keyed by device id exactly like [BleService.connectionState].
///
/// This is the integration point the rest of the app should read
/// `motionClass`/`motionConfidence` from — see [MotionData]. It does not
/// compute, reference, or feed a Threat Score; it only exposes what the
/// glove actually said. Malformed notifications are dropped silently (see
/// [parseMotionPacket]) rather than surfaced as a stream error, so one bad
/// packet never tears down the subscription or crashes a listening widget.
///
/// `autoDispose` + `family`: each distinct `deviceId` gets its own
/// subscription, torn down when nothing is watching it anymore. This
/// provider does not itself connect, reconnect, or otherwise manage
/// connection lifecycle — same contract as
/// `BleService.characteristicNotifications`. There is currently no
/// app-wide "stay connected to the glove" owner outside the pairing flow
/// (see the note on connection ownership in `BlePairingController`'s doc
/// comment in `ble_providers.dart`) — that is a pre-existing gap in this
/// codebase, not something this provider attempts to solve. Wire it up to
/// whatever eventually owns that connection (today: while
/// `BlePairingController`'s stage is `connected`/`registered` for this
/// `deviceId`).
final motionDataProvider = StreamProvider.autoDispose.family<MotionData, String>((ref, deviceId) {
  final bleService = ref.watch(bleServiceProvider);
  return bleService
      .characteristicNotifications(
        deviceId,
        serviceUuid: kGloveMotionServiceUuid,
        characteristicUuid: kGloveMotionCharacteristicUuid,
      )
      .map(parseMotionPacket)
      .where((data) => data != null)
      .cast<MotionData>()
      // TEMPORARY DEBUG LOGGING — for visually verifying the real ESP32 ->
      // BLE -> Flutter data flow. Remove once verification is done. Purely
      // an observer: does not alter `data`, parsing behaviour, or anything
      // downstream, and never fires for a packet that failed to parse
      // (those are already filtered out above).
      .map((data) {
        debugPrint('[SAFEHER MOTION]');
        debugPrint('CLASS=${data.classification}');
        debugPrint('CONFIDENCE=${data.confidence}');
        return data;
      });
});

/// The most recent [MotionData] for [deviceId] while its BLE link is
/// genuinely up — `null` before the first packet of a connection episode,
/// and reset to `null` the instant [gloveConnectionStateProvider] reports
/// [BleConnectionStatus.disconnected], rather than continuing to reflect
/// whatever packet arrived last.
///
/// Deliberately not just "the current value of [motionDataProvider]": a
/// [StreamProvider] keeps its last [AsyncValue.value] on screen through a
/// rebuild or an error by design, and `characteristicNotifications` never
/// errors or closes on a real disconnect — it just goes quiet (see its doc
/// comment) — so [motionDataProvider] alone cannot tell a live reading from
/// a stale one. This uses `ref.listen` instead of `ref.watch` specifically
/// so it can *clear* its state on disconnect rather than only ever
/// replacing it with newer data.
///
/// Also the one place that forces [motionDataProvider] to actually
/// re-subscribe on a real reconnect: `ref.invalidate` is called only on a
/// genuine disconnected→connected (or connected→disconnected) edge,
/// detected by comparing `previous`/`next` here — not on every incidental
/// resolution of [gloveConnectionStateProvider] (e.g. its first
/// loading→data settle), which would otherwise risk tearing down and
/// recreating the subscription while a real notification is in flight.
class LiveMotionDataNotifier extends AutoDisposeFamilyNotifier<MotionData?, String> {
  @override
  MotionData? build(String deviceId) {
    ref.listen<AsyncValue<BleConnectionStatus>>(gloveConnectionStateProvider(deviceId), (previous, next) {
      final wasConnected = previous?.valueOrNull == BleConnectionStatus.connected;
      final isConnected = next.valueOrNull == BleConnectionStatus.connected;
      if (isConnected == wasConnected) return;
      if (isConnected) {
        // A fresh connection episode (first connect, or a real reconnect
        // after a drop): rebuild `motionDataProvider` so it opens a brand
        // new GATT subscription rather than relying on one whose notify
        // flag died with the old link.
        ref.invalidate(motionDataProvider(deviceId));
      } else {
        state = null;
        ref.invalidate(motionDataProvider(deviceId));
      }
    }, fireImmediately: true);
    ref.listen<AsyncValue<MotionData>>(motionDataProvider(deviceId), (previous, next) {
      // `next.isLoading` is true, briefly, right after the `ref.invalidate`
      // above rebuilds this provider — and during that window `next` can
      // still carry the *previous* connection episode's last value (a
      // `StreamProvider` rebuild keeps showing old data until the new
      // stream's first event arrives, by design). Skipping loading states
      // here is what keeps a stale pre-disconnect/-reconnect reading from
      // briefly flashing back before a genuinely fresh packet arrives.
      if (next.isLoading) return;
      final data = next.valueOrNull;
      if (data != null) state = data;
    });
    return null;
  }
}

final liveMotionDataProvider = NotifierProvider.autoDispose
    .family<LiveMotionDataNotifier, MotionData?, String>(LiveMotionDataNotifier.new);

/// Derived, read-only view of [liveMotionDataProvider]: `severity *
/// confidence * 100` for the same glove, via [computeMotionRiskScore].
/// `null` whenever there is no current live reading — no packet yet, or the
/// glove is offline — callers should render that as "no data" (`--`)
/// rather than a score of 0, since 0 is also NORMAL's genuine value.
///
/// This is a separate, glove-local signal — not the app's overall Threat
/// Score (owned elsewhere) and not folded into it here. It does not open a
/// second BLE subscription: [liveMotionDataProvider] reuses
/// [motionDataProvider]'s existing stream rather than creating another one.
final motionRiskScoreProvider = Provider.autoDispose.family<double?, String>((ref, deviceId) {
  final motion = ref.watch(liveMotionDataProvider(deviceId));
  return motion == null ? null : computeMotionRiskScore(motion);
});
