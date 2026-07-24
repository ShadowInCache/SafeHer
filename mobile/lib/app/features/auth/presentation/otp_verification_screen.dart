import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/state/session_controller.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _phoneController = TextEditingController(text: '+91');
  final _otpController = TextEditingController();
  AppRole _role = AppRole.user;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (next.authenticated) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (_) => false,
        );
      }
    });

    final session = ref.watch(sessionControllerProvider);
    final hasOtpSession = session.pendingOtpVerificationId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('OTP Verification')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Secure phone login',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Request OTP and verify to access SafeHer quickly in emergencies.',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AppRole>(
            initialValue: _role,
            decoration: const InputDecoration(
              labelText: 'Role',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            onChanged: (value) {
              if (value != null) {
                setState(() => _role = value);
              }
            },
            items: AppRole.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.name)),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: session.loading
                ? null
                : () {
                    ref
                        .read(sessionControllerProvider.notifier)
                        .startPhoneOtp(_phoneController.text.trim());
                  },
            child: session.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Request OTP'),
          ),
          const SizedBox(height: 18),
          if (hasOtpSession) ...[
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP code',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: session.loading
                  ? null
                  : () {
                      ref
                          .read(sessionControllerProvider.notifier)
                          .verifyPhoneOtp(
                            smsCode: _otpController.text.trim(),
                            role: _role,
                          );
                    },
              child: const Text('Verify & Continue'),
            ),
          ],
          if (session.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              session.errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }
}
