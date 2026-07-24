import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class DevicePairingFeatureScreen extends ConsumerStatefulWidget {
  const DevicePairingFeatureScreen({super.key});

  @override
  ConsumerState<DevicePairingFeatureScreen> createState() =>
      _DevicePairingFeatureScreenState();
}

class _DevicePairingFeatureScreenState
    extends ConsumerState<DevicePairingFeatureScreen> {
  bool _scanning = false;
  List<BluetoothDevice> _devices = [];

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final result = await ref
        .read(safetyControllerProvider.notifier)
        .scanWearables();
    if (mounted) {
      setState(() {
        _devices = result;
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safety = ref.watch(safetyControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wearable Device Pairing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _statusCard(safety.glove)),
              const SizedBox(width: 10),
              Expanded(child: _statusCard(safety.glasses)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(
                    _scanning ? 'Scanning...' : 'Scan Nearby Devices',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_devices.isEmpty)
            const GlassCard(
              child: Text(
                'No wearable found yet. Keep glove/glasses in pairing mode.',
              ),
            )
          else
            ..._devices.map((device) => _deviceTile(device)),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device Actions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _runDiagnostics(DeviceKind.glove),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Glove Diagnostics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _runDiagnostics(DeviceKind.glasses),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Glasses Diagnostics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _calibrate(DeviceKind.glove),
                      icon: const Icon(Icons.tune),
                      label: const Text('Calibrate Glove'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _calibrate(DeviceKind.glasses),
                      icon: const Icon(Icons.tune),
                      label: const Text('Calibrate Glasses'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _firmwareUpdate,
                      icon: const Icon(Icons.system_update_alt),
                      label: const Text('Firmware Update'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection Logs',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (safety.connectionLogs.isEmpty)
                  const Text('No connection logs yet.')
                else
                  ...safety.connectionLogs
                      .take(20)
                      .map(
                        (line) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            line,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard(WearableDeviceState device) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('Connected: ${device.connected ? 'Yes' : 'No'}'),
          Text('Battery: ${device.battery}%'),
          Text('Signal: ${device.signalStrength}%'),
          Text('Transport: ${device.transport.name.toUpperCase()}'),
        ],
      ),
    );
  }

  Widget _deviceTile(BluetoothDevice device) {
    final lowerName = device.platformName.toLowerCase();
    final inferredKind = lowerName.contains('glove')
        ? DeviceKind.glove
        : DeviceKind.glasses;

    return Card(
      child: ListTile(
        leading: Icon(
          inferredKind == DeviceKind.glove
              ? Icons.back_hand_outlined
              : Icons.visibility_outlined,
        ),
        title: Text(
          device.platformName.isEmpty
              ? 'Unknown Wearable'
              : device.platformName,
        ),
        subtitle: Text(device.remoteId.toString()),
        trailing: ElevatedButton(
          onPressed: () async {
            final ok = await ref
                .read(safetyControllerProvider.notifier)
                .pairWearable(kind: inferredKind, device: device);
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? 'Pairing successful' : 'Pairing failed'),
              ),
            );
          },
          child: const Text('Pair'),
        ),
      ),
    );
  }

  Future<void> _runDiagnostics(DeviceKind kind) async {
    final report = await ref
        .read(safetyControllerProvider.notifier)
        .runDiagnostics(kind);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(report)));
  }

  Future<void> _calibrate(DeviceKind kind) async {
    await ref.read(safetyControllerProvider.notifier).calibrateWearable(kind);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${kind.name} calibration completed')),
    );
  }

  void _firmwareUpdate() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Firmware update queued for connected wearables.'),
      ),
    );
  }
}
