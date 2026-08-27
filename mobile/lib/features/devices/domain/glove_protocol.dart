import '../../../shared/models/threat_level.dart';

/// The BLE contract between the SafeHer glove firmware and this app.
///
/// Kept in one file, on purpose: the firmware and the app are separate
/// codebases that have to agree exactly, and a UUID or field order that
/// drifts fails silently — the glove notifies into the void and the app shows
/// zeros, which is precisely the state this was written to get out of.
///
/// **Firmware:** `glove/firmware/SafeHer_Glove_V5_OnDevice.ino`.
///
/// ## The wire format
///
/// Two notify characteristics on one service, because the two streams have
/// different rates and different meanings. Classification fires per inference
/// window; telemetry ticks steadily so the UI has something live to show even
/// when nothing is happening.
///
/// * classification — `"<LABEL>,<confidence>"`   e.g. `FALL,0.93`
/// * telemetry      — `"<accelG>,<gyroDps>,<bpm>,<batteryPct>"`
///                     e.g. `1.02,4.3,78,86`
///
/// Plain CSV rather than JSON: an ESP32 building a string with `snprintf` has
/// no room for a parser, and the payload has to fit in a single 20-byte BLE
/// notification on older stacks.
abstract final class GloveBle {
  /// Advertised name. The firmware sets this in `BLEDevice::init`.
  static const deviceName = 'SafeHer-Glove';

  /// The service the firmware currently exposes.
  ///
  /// This and [classificationCharacteristicUuid] are the stock UUIDs from the
  /// Arduino `BLE_notify` example. They work, but they are not unique to
  /// SafeHer -- any other device built from that sample advertises the same
  /// service, and a scan filtered on it would match a stranger's project.
  /// [suggestedPrivateServiceUuid] is a generated replacement for when the
  /// firmware can be reflashed; changing it is a coordinated change on both
  /// sides, which is why it is recorded rather than silently swapped.
  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';

  /// Notifies `"<LABEL>,<confidence>"` when the on-device model classifies a
  /// motion window.
  static const classificationCharacteristicUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  /// Notifies `"<accelG>,<gyroDps>,<bpm>,<batteryPct>"` on a timer.
  ///
  /// New in this revision, so the app tolerates its absence: a glove running
  /// older firmware simply never notifies here and the readings stay unknown,
  /// rather than the connection failing.
  static const telemetryCharacteristicUuid = '33b4fb00-9c17-4ad2-8fc9-89ad6dbc76bd';

  /// Replacements for the stock example UUIDs, for a future firmware flash.
  static const suggestedPrivateServiceUuid = '2f56491c-849f-48f5-9355-35bc69dca64b';
  static const suggestedPrivateClassificationUuid =
      '8cf28114-4f06-465d-910b-d03ec40e5ff3';
}

/// One classification from the on-device model.
class GloveClassification {
  const GloveClassification({required this.label, required this.confidence});

  /// The raw label as the firmware sent it, e.g. `FALL`.
  ///
  /// Kept verbatim rather than parsed into an enum at the boundary: firmware
  /// that adds an eighth class should show up as an unknown label in the UI,
  /// not crash the parser or get silently mapped to something wrong.
  final String label;

  /// 0.0-1.0, as reported by the model.
  final double confidence;

  /// The seven classes the v5 model was trained on, in label order.
  static const knownLabels = <String>[
    'NORMAL',
    'JERK',
    'PUSH',
    'PULL',
    'SHAKING',
    'TWISTING',
    'FALL',
  ];

  bool get isKnown => knownLabels.contains(label);

  /// How this class maps onto the app's threat scale.
  ///
  /// **This is a product decision, not a technical one, and it is the one
  /// worth arguing about.** A false negative on `FALL` is someone lying hurt
  /// with no alarm raised. A false positive on `SHAKING` is contacts phoned
  /// because someone shook their hand dry, which is not merely embarrassing:
  /// it is how people learn to switch the feature off, and a disabled feature
  /// protects nobody.
  ///
  /// So the mapping is deliberately conservative. `FALL` is the only class
  /// treated as danger. `PUSH` and `PULL` describe force applied by someone
  /// else and are raised to elevated. `JERK`, `SHAKING` and `TWISTING` all
  /// occur constantly in ordinary use -- a bag lifted, a hand dried, a jar
  /// opened -- and stay at caution. Nothing here dispatches on its own; the
  /// threshold and the fusion layer decide that, and this only says how
  /// alarming the movement looked.
  ThreatLevel get threatLevel => switch (label) {
    'FALL' => ThreatLevel.danger,
    'PUSH' || 'PULL' => ThreatLevel.elevated,
    'JERK' || 'SHAKING' || 'TWISTING' => ThreatLevel.caution,
    _ => ThreatLevel.safe,
  };

  /// Sentence-case for display: the firmware shouts in capitals because C
  /// string constants are easier that way, not because the UI should.
  String get displayLabel =>
      label.isEmpty ? 'Unknown' : label[0] + label.substring(1).toLowerCase();

  /// Parses `"<LABEL>,<confidence>"`.
  ///
  /// Returns null rather than throwing on anything malformed. A garbled
  /// notification is a dropped reading, not a crash: BLE payloads arrive
  /// truncated often enough that a parser which throws would take the app
  /// down in the field.
  static GloveClassification? tryParse(String raw) {
    final parts = raw.trim().split(',');
    if (parts.length < 2) return null;

    final label = parts[0].trim().toUpperCase();
    if (label.isEmpty) return null;

    final confidence = double.tryParse(parts[1].trim());
    if (confidence == null || confidence.isNaN) return null;

    return GloveClassification(
      label: label,
      // Clamped: a firmware bug reporting 1.4 should not travel through the
      // app as a confidence above certainty.
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  @override
  String toString() => 'GloveClassification($label, $confidence)';
}

/// One telemetry tick from the glove.
///
/// Every field is nullable because the firmware may send fewer than four
/// values -- older builds, or a sensor that failed to initialise. An absent
/// reading and a reading of zero mean very different things: `0 bpm` is a
/// claim about a heart, and this app should never make that claim by
/// accident.
class GloveTelemetry {
  const GloveTelemetry({
    this.accelG,
    this.gyroDps,
    this.heartRateBpm,
    this.batteryPercent,
  });

  final double? accelG;
  final double? gyroDps;

  /// Beats per minute from the pulse sensor. Replaces the flex reading the
  /// UI used to show, which no hardware ever produced.
  final double? heartRateBpm;

  /// 0-100, as the firmware reports it.
  final double? batteryPercent;

  bool get hasAny =>
      accelG != null || gyroDps != null || heartRateBpm != null || batteryPercent != null;

  /// Parses `"<accelG>,<gyroDps>,<bpm>,<batteryPct>"`.
  ///
  /// Tolerant by field: a trailing value the firmware has not implemented yet
  /// simply stays null, so telemetry does not have to arrive complete to be
  /// useful.
  static GloveTelemetry? tryParse(String raw) {
    final parts = raw.trim().split(',');
    if (parts.isEmpty) return null;

    double? at(int index) {
      if (index >= parts.length) return null;
      final value = double.tryParse(parts[index].trim());
      return (value == null || value.isNaN) ? null : value;
    }

    final telemetry = GloveTelemetry(
      accelG: at(0),
      gyroDps: at(1),
      heartRateBpm: at(2),
      batteryPercent: at(3)?.clamp(0.0, 100.0),
    );
    return telemetry.hasAny ? telemetry : null;
  }

  @override
  String toString() =>
      'GloveTelemetry(accel: $accelG, gyro: $gyroDps, bpm: $heartRateBpm, battery: $batteryPercent)';
}
