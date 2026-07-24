import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class GuardianTrackingScreenV2 extends ConsumerWidget {
  const GuardianTrackingScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final notifier = ref.read(safetyControllerProvider.notifier);
    final guardians = safety.contacts.where((c) => c.isGuardian).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Guardian Tracking')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: SwitchListTile(
              value: safety.guardianMode,
              onChanged: notifier.setGuardianMode,
              title: const Text('Family Live Tracking Mode'),
              subtitle: const Text(
                'Share continuous location with selected guardians',
              ),
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Location: ${safety.currentLocation.latitude.toStringAsFixed(5)}, ${safety.currentLocation.longitude.toStringAsFixed(5)}',
                ),
                Text('Threat score: ${safety.threatScore.toStringAsFixed(1)}'),
                Text(
                  'Live sharing: ${safety.liveLocationSharing ? 'ON' : 'OFF'}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Guardians',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (guardians.isEmpty)
                  const Text('No guardian contacts configured.')
                else
                  ...guardians.map(
                    (guardian) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_pin_circle_outlined),
                      title: Text(guardian.name),
                      subtitle: Text(
                        '${guardian.relationship} • ${guardian.phone}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Live location pushed to guardians.'),
                ),
              );
            },
            icon: const Icon(Icons.share_location_outlined),
            label: const Text('Share Live Location Now'),
          ),
        ],
      ),
    );
  }
}
