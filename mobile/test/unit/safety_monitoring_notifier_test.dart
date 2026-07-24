import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/shared/models/domain_models.dart';
import 'package:safeher_app/app/shared/state/safety_monitoring_notifier.dart';

void main() {
  test('initial state is safe and initializing', () {
    final notifier = SafetyMonitoringNotifier();

    expect(notifier.state.initializing, isTrue);
    expect(notifier.state.threatLevel, ThreatLevelState.safe);
    expect(notifier.state.monitoringEnabled, isFalse);
  });

  test('updateRealtimeSignal appends event and updates threat values', () {
    final notifier = SafetyMonitoringNotifier();
    final event = ThreatEvent(
      id: 'e1',
      time: DateTime.now(),
      source: 'ws',
      description: 'Threat update',
      confidence: 0.8,
      severity: ThreatLevelState.danger,
    );

    notifier.updateRealtimeSignal(
      event: event,
      threatScore: 80,
      threatLevel: ThreatLevelState.danger,
      connectionLogs: const ['log-1'],
    );

    expect(notifier.state.timeline, hasLength(1));
    expect(notifier.state.threatScore, 80);
    expect(notifier.state.threatLevel, ThreatLevelState.danger);
    expect(notifier.state.connectionLogs, contains('log-1'));
  });

  test('setWearableConnected updates targeted wearable', () {
    final notifier = SafetyMonitoringNotifier();
    final glove = WearableDeviceState.initial(
      DeviceKind.glove,
    ).copyWith(connected: true, battery: 91);

    notifier.setWearableConnected(
      kind: DeviceKind.glove,
      wearable: glove,
      connectionLogs: const ['paired glove'],
    );

    expect(notifier.state.glove.connected, isTrue);
    expect(notifier.state.glove.battery, 91);
    expect(notifier.state.glasses.connected, isFalse);
  });
}
