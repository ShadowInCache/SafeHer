import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../shared/state/providers.dart';

class PrivacyConsentScreen extends ConsumerStatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  ConsumerState<PrivacyConsentScreen> createState() =>
      _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends ConsumerState<PrivacyConsentScreen> {
  bool _privacy = false;
  bool _terms = false;
  bool _aiConsent = false;

  @override
  Widget build(BuildContext context) {
    final accepted = _privacy && _terms && _aiConsent;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Consent')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your trust and safety come first',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          const Text(
            'SafeHer uses location, audio/video evidence, and wearable telemetry only for emergency detection and response workflows.',
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: _privacy,
            onChanged: (value) => setState(() => _privacy = value ?? false),
            title: const Text('I accept the Privacy Policy'),
            subtitle: const Text(
              'Data is encrypted and stored securely for incident evidence.',
            ),
          ),
          CheckboxListTile(
            value: _terms,
            onChanged: (value) => setState(() => _terms = value ?? false),
            title: const Text('I accept the Terms of Service'),
            subtitle: const Text(
              'Emergency flows and wearable controls are used responsibly.',
            ),
          ),
          CheckboxListTile(
            value: _aiConsent,
            onChanged: (value) => setState(() => _aiConsent = value ?? false),
            title: const Text('I consent to contextual AI safety analysis'),
            subtitle: const Text(
              'AI detects motion/voice/vision anomalies to prevent threats proactively.',
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: !accepted
                ? null
                : () async {
                    await ref
                        .read(sessionControllerProvider.notifier)
                        .acceptConsent(true);
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.permissionsSetup,
                      );
                    }
                  },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
