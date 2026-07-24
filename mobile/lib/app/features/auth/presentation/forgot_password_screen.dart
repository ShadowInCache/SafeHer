import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/state/providers.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Reset your password securely',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Account Email',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: session.loading
                ? null
                : () async {
                    await ref
                        .read(sessionControllerProvider.notifier)
                        .requestPasswordReset(_emailController.text.trim());
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'If account exists, reset instructions were sent.',
                        ),
                      ),
                    );
                  },
            child: const Text('Send Reset Link'),
          ),
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
