import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/app_routes.dart';
import '../../../shared/state/providers.dart';

class PermissionsSetupScreen extends ConsumerStatefulWidget {
  const PermissionsSetupScreen({super.key});

  @override
  ConsumerState<PermissionsSetupScreen> createState() =>
      _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState
    extends ConsumerState<PermissionsSetupScreen> {
  Map<Permission, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    final statuses = await ref
        .read(bootstrapBundleProvider)
        .permissionsService
        .checkStatuses();
    if (mounted) {
      setState(() => _statuses = statuses);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allGranted =
        _statuses.values.isNotEmpty &&
        _statuses.values
            .where((status) => status.isDenied || status.isPermanentlyDenied)
            .isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Permissions Setup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Enable critical safety permissions',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text(
            'SafeHer needs camera, microphone, GPS, Bluetooth, notifications, contacts, and communication permissions to protect you in real emergencies.',
          ),
          const SizedBox(height: 18),
          ..._statuses.entries.map((entry) {
            final permission = entry.key;
            final status = entry.value;
            return ListTile(
              dense: true,
              leading: Icon(
                status.isGranted ? Icons.check_circle : Icons.error_outline,
                color: status.isGranted ? Colors.green : Colors.orange,
              ),
              title: Text(permission.toString().split('.').last),
              subtitle: Text(status.toString().split('.').last),
            );
          }),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(bootstrapBundleProvider)
                  .permissionsService
                  .requestEssential();
              await _refreshStatuses();
            },
            child: const Text('Request Essential Permissions'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await ref
                  .read(bootstrapBundleProvider)
                  .permissionsService
                  .requestAll();
              await _refreshStatuses();
            },
            child: const Text('Request All Permissions'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: openAppSettings,
            child: const Text('Open device settings'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: !allGranted
                ? null
                : () async {
                    await ref
                        .read(sessionControllerProvider.notifier)
                        .completePermissionsSetup();
                    if (!context.mounted) {
                      return;
                    }
                    final target =
                        ref.read(sessionControllerProvider).authenticated
                        ? AppRoutes.home
                        : AppRoutes.login;
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      target,
                      (_) => false,
                    );
                  },
            child: const Text('Activate SafeHer'),
          ),
        ],
      ),
    );
  }
}
