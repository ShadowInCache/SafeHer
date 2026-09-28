import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/motion_data.dart';
import '../domain/models/motion_risk_score.dart';
import 'glove_link_providers.dart';

/// `severity * confidence * 100` for whatever the glove most recently
/// reported, via [computeMotionRiskScore]. `null` whenever there is no
/// current live reading — not yet connected, or no classification packet
/// received this connection episode — callers should render that as
/// "no data" (`--`) rather than a score of 0, since 0 is also NORMAL's
/// genuine value.
///
/// Reads [gloveLinkProvider] rather than opening its own BLE subscription.
/// An earlier version of this provider (`motionDataProvider` /
/// `liveMotionDataProvider`) subscribed to the classification characteristic
/// independently of [GloveLink], which already does the same thing to drive
/// the device card's classification row. Two independent notification
/// subscriptions on the same GATT characteristic is not something Android's
/// BLE stack handles reliably — in practice one of them starved: telemetry
/// (a separate characteristic) kept working, classification did not. There
/// is exactly one subscription to the classification characteristic now,
/// owned by [GloveLink]; this provider only reads its state.
///
/// This is a separate, glove-local signal — not the app's overall Threat
/// Score (owned elsewhere) and not folded into it here.
///
/// The `deviceId` parameter is kept for call-site compatibility (callers
/// already gate on `deviceId == connectedGloveIdProvider`'s value) even
/// though [GloveLink] itself tracks whichever single glove is currently
/// paired, not a per-device family — this app supports one connected glove
/// at a time.
final motionRiskScoreProvider = Provider.autoDispose.family<double?, String>((ref, deviceId) {
  final classification = ref.watch(gloveLinkProvider).classification;
  if (classification == null) return null;
  return computeMotionRiskScore(
    MotionData(classification: classification.label, confidence: classification.confidence),
  );
});

/// The most recent raw classification label the glove reported (e.g.
/// `FALL`, `SUDDEN_MOVEMENT`), or `null` before the first packet of a
/// connection episode. See [motionRiskScoreProvider] for why this reads
/// [gloveLinkProvider] instead of subscribing independently.
final liveMotionClassificationProvider = Provider.autoDispose.family<String?, String>((ref, deviceId) {
  return ref.watch(gloveLinkProvider).classification?.label;
});
