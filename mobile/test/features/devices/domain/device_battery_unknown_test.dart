import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';

/// The glove reports no battery level at all. Rendering that as `0%` with
/// `~0h remaining` told the user her safety device was flat when nobody had
/// ever asked it — the same absent-is-not-zero mistake the sensor readings on
/// this model were already fixed for.
void main() {
  DeviceDetail device({double? battery, int? hours}) => DeviceDetail(
        id: 'g1',
        name: 'SafeHer-Glove',
        type: DeviceType.glove,
        isOnline: true,
        batteryPercent: battery,
        batteryHoursRemaining: hours,
        signalStrength: 3,
        firmwareVersion: '1.0.0',
        updateAvailable: false,
        sensors: const SensorReading.unknown(),
      );

  test('a device that never reported a battery level has none, not zero', () {
    final d = device();
    expect(d.batteryPercent, isNull);
    expect(d.batteryHoursRemaining, isNull);
  });

  test('battery fields are optional so unknown is representable', () {
    // If these were required and non-nullable, every construction site would
    // be forced to invent a number — which is how 0% got there.
    expect(() => device(), returnsNormally);
  });

  test('a genuine zero is still distinguishable from unknown', () {
    final flat = device(battery: 0, hours: 0);
    expect(flat.batteryPercent, 0);
    expect(flat.batteryHoursRemaining, 0);
    expect(flat.batteryPercent, isNotNull,
        reason: 'a real flat battery must not read the same as no report');
  });

  test('a reported level is carried through unchanged', () {
    final d = device(battery: 0.82, hours: 36);
    expect(d.batteryPercent, closeTo(0.82, 1e-9));
    expect(d.batteryHoursRemaining, 36);
  });

  test('sensors remain unknown rather than zero, as before', () {
    final s = device().sensors;
    expect(s.accelG, isNull);
    expect(s.gyroDps, isNull);
    expect(s.heartRateBpm, isNull);
    expect(s.hasAny, isFalse);
  });
}
