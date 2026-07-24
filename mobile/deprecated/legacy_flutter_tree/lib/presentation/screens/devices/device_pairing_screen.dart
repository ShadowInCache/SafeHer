import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../providers/device_provider.dart';

class DevicePairingScreen extends ConsumerStatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  ConsumerState<DevicePairingScreen> createState() =>
      _DevicePairingScreenState();
}

class _DevicePairingScreenState extends ConsumerState<DevicePairingScreen> {
  List<BluetoothDevice> _availableDevices = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _checkBluetoothAndScan();
  }

  Future<void> _checkBluetoothAndScan() async {
    try {
      final isAvailable = await ref.read(bluetoothAvailableProvider.future);
      if (isAvailable && mounted) {
        _startScan();
      } else {
        _showBluetoothDisabledDialog();
      }
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    final devices = await ref.read(deviceProvider.notifier).scanForDevices();
    if (mounted) {
      setState(() {
        _availableDevices = devices;
        _isScanning = false;
      });
    }
  }

  void _showBluetoothDisabledDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Disabled'),
        content: const Text('Please enable Bluetooth to pair devices.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device, bool isGlove) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final success = isGlove
        ? await ref.read(deviceProvider.notifier).connectToGlove(device)
        : await ref.read(deviceProvider.notifier).connectToGlasses(device);

    if (mounted) Navigator.pop(context);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${isGlove ? "Glove" : "Glasses"} connected'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Connection failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Devices'),
        actions: [
          if (!_isScanning)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startScan,
              tooltip: 'Scan',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _StatusCard(
                    'Glove',
                    deviceState.gloveConnected,
                    deviceState.gloveBattery,
                    Icons.back_hand,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatusCard(
                    'Glasses',
                    deviceState.glassesConnected,
                    deviceState.glassesBattery,
                    Icons.remove_red_eye,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Scanning...'),
                ],
              ),
            ),
          Expanded(
            child: _availableDevices.isEmpty && !_isScanning
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bluetooth_disabled,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No devices found',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.search),
                          label: const Text('Start Scanning'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _availableDevices.length,
                    itemBuilder: (context, index) {
                      final device = _availableDevices[index];
                      final isGlove = device.platformName
                          .toLowerCase()
                          .contains('glove');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Icon(
                            isGlove ? Icons.back_hand : Icons.remove_red_eye,
                          ),
                          title: Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Unknown',
                          ),
                          subtitle: Text(device.remoteId.toString()),
                          trailing: ElevatedButton(
                            onPressed: () => _connectToDevice(device, isGlove),
                            child: const Text('Connect'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String title;
  final bool isConnected;
  final int battery;
  final IconData icon;

  const _StatusCard(this.title, this.isConnected, this.battery, this.icon);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isConnected ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isConnected ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            if (isConnected) ...[
              const SizedBox(height: 4),
              Text(
                '$battery%',
                style: TextStyle(
                  fontSize: 10,
                  color: battery < 20 ? Colors.red : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
