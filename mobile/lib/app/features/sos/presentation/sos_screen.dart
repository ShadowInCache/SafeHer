import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class SosActivationScreen extends ConsumerWidget {
  const SosActivationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final notifier = ref.read(safetyControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency SOS')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          GlassCard(
            tint: PremiumTheme.danger,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'One-tap emergency flow',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Triggers live location sharing, guardian alerts, police escalation, and encrypted evidence handoff.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: GestureDetector(
              onTap: () {
                if (safety.sosPending) {
                  notifier.cancelSos();
                } else {
                  notifier.triggerSos(auto: false);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: safety.sosPending ? 190 : 220,
                height: safety.sosPending ? 190 : 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFF97316)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: PremiumTheme.danger.withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        safety.sosPending
                            ? safety.sosCountdown.toString()
                            : 'SOS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        safety.sosPending ? 'Tap to cancel' : 'Tap to activate',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Controls',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: safety.voiceCommandEnabled,
                  onChanged: notifier.setVoiceCommandEnabled,
                  title: const Text('Voice trigger: "Help me"'),
                  subtitle: const Text('Hands-free emergency activation'),
                ),
                SwitchListTile(
                  value: safety.fakeCallEnabled,
                  onChanged: notifier.setFakeCallEnabled,
                  title: const Text('Fake incoming call quick action'),
                  subtitle: const Text(
                    'Discreet escape support when threatened',
                  ),
                ),
                SwitchListTile(
                  value: safety.liveLocationSharing,
                  onChanged: (_) {},
                  title: const Text('Live location streaming'),
                  subtitle: const Text('Automatically enabled during SOS'),
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
                  'Auto-response Stack',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sms_outlined),
                  title: Text('Emergency SMS + push notifications'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.video_camera_back_outlined),
                  title: Text('Auto audio/video evidence recording'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.campaign_outlined),
                  title: Text('Wearable buzzer and loud alarm trigger'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.flash_on_outlined),
                  title: Text('Extreme threat: glove shock mechanism request'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Fake incoming call started.')),
              );
            },
            icon: const Icon(Icons.call),
            label: const Text('Trigger Fake Incoming Call'),
          ),
        ],
      ),
    );
  }
}
