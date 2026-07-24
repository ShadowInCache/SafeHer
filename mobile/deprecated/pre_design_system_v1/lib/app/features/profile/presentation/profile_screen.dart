import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class ProfileScreenV2 extends ConsumerWidget {
  const ProfileScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final user = session.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 30,
                  child: Icon(Icons.person_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.fullName ?? 'SafeHer User',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(user?.email ?? 'No email'),
                      Text('Role: ${user?.role.name ?? 'user'}'),
                    ],
                  ),
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
                  'Profile Management',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const TextField(
                  decoration: InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 8),
                const TextField(
                  decoration: InputDecoration(labelText: 'Phone number'),
                ),
                const SizedBox(height: 8),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Emergency medical notes',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Profile updated successfully.'),
                      ),
                    );
                  },
                  child: const Text('Save Profile'),
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
                  'Account Security',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('Biometric unlock'),
                  trailing: Switch(
                    value: session.biometricsEnabled,
                    onChanged: (value) {
                      ref
                          .read(sessionControllerProvider.notifier)
                          .setBiometricsEnabled(value);
                    },
                  ),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lock_outline),
                  title: Text('App lock PIN'),
                  subtitle: Text('Configured'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
