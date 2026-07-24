import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../shared/models/domain_models.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/state/session_controller.dart';
import '../../../shared/widgets/glass_card.dart';

class AuthSignupScreen extends ConsumerStatefulWidget {
  const AuthSignupScreen({super.key});

  @override
  ConsumerState<AuthSignupScreen> createState() => _AuthSignupScreenState();
}

class _AuthSignupScreenState extends ConsumerState<AuthSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  AppRole _role = AppRole.user;
  bool _accepted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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

    return Scaffold(
      appBar: AppBar(title: const Text('Create SafeHer account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Secure signup',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().length < 2)
                          ? 'Enter full name'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) =>
                          (value == null || !value.contains('@'))
                          ? 'Enter valid email'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) => (value == null || value.length < 6)
                          ? 'Use at least 6 characters'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<AppRole>(
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: AppRole.values
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role.name),
                            ),
                          )
                          .toList(),
                      onChanged: (role) {
                        if (role != null) {
                          setState(() => _role = role);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _accepted,
                      onChanged: (value) =>
                          setState(() => _accepted = value ?? false),
                      title: const Text(
                        'I accept Terms, Privacy Policy, and emergency data consent.',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (session.errorMessage != null)
                      Text(
                        session.errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: session.loading ? null : _signup,
                      child: session.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create Account'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.login,
                      ),
                      child: const Text('Already have an account? Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _signup() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept terms and privacy consent'),
        ),
      );
      return;
    }

    ref
        .read(sessionControllerProvider.notifier)
        .signUpWithEmail(
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          role: _role,
        );
  }
}
