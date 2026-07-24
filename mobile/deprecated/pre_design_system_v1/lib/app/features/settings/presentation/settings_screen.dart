import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class SettingsScreenV2 extends ConsumerWidget {
  const SettingsScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final safety = ref.watch(safetyControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {session.themeMode},
                onSelectionChanged: (selection) {
                  ref
                      .read(sessionControllerProvider.notifier)
                      .setThemeMode(selection.first);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Locale>(
                initialValue: session.locale,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: Locale('en'), child: Text('English')),
                  DropdownMenuItem(value: Locale('hi'), child: Text('Hindi')),
                  DropdownMenuItem(value: Locale('ta'), child: Text('Tamil')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(sessionControllerProvider.notifier)
                        .setLocale(value);
                  }
                },
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
                'Safety Controls',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Alert sensitivity: ${safety.alertSensitivity}%'),
              Slider(
                value: safety.alertSensitivity.toDouble(),
                min: 40,
                max: 95,
                divisions: 11,
                label: '${safety.alertSensitivity}%',
                onChanged: (value) {
                  ref
                      .read(safetyControllerProvider.notifier)
                      .setAlertSensitivity(value.round());
                },
              ),
              SwitchListTile(
                value: safety.voiceCommandEnabled,
                onChanged: ref
                    .read(safetyControllerProvider.notifier)
                    .setVoiceCommandEnabled,
                title: const Text('Voice command trigger ("Help me")'),
              ),
              SwitchListTile(
                value: safety.fakeCallEnabled,
                onChanged: ref
                    .read(safetyControllerProvider.notifier)
                    .setFakeCallEnabled,
                title: const Text('Fake incoming call feature'),
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
                'Privacy & Permissions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Permission manager'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.permissionsSetup),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Privacy policy and consent'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.privacyConsent),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Emergency contacts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.emergencyContacts),
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
                'Backup & Restore',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Encrypted backup started.')),
                  );
                },
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Backup now'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Restore wizard opened.')),
                  );
                },
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restore backup'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () async {
            await ref.read(sessionControllerProvider.notifier).logout();
            if (!context.mounted) {
              return;
            }
            Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.login,
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('Logout'),
        ),
      ],
    );
  }
}
