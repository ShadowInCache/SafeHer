import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/inputs/sa_password_field.dart';
import '../../../shared/components/inputs/sa_phone_field.dart';
import '../../../shared/components/inputs/sa_text_field.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import 'signup_controller.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _firstNameError;
  String? _lastNameError;
  String? _emailError;
  String? _phoneError;
  String? _passwordError;
  String? _confirmPasswordError;
  int _passwordStrength = 0;

  static const _countryCode = '+1';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _allValid =>
      _firstNameController.text.trim().isNotEmpty &&
      _lastNameController.text.trim().isNotEmpty &&
      _emailRegex.hasMatch(_emailController.text.trim()) &&
      _phoneController.text.replaceAll(RegExp(r'\D'), '').length >= 7 &&
      _passwordStrength == 4 &&
      _confirmPasswordController.text == _passwordController.text &&
      _confirmPasswordController.text.isNotEmpty;

  /// Validates top-to-bottom, surfacing only the first invalid field's
  /// error so re-tapping progressively reveals the next issue.
  bool _validate() {
    setState(() {
      _firstNameError = null;
      _lastNameError = null;
      _emailError = null;
      _phoneError = null;
      _passwordError = null;
      _confirmPasswordError = null;

      if (_firstNameController.text.trim().isEmpty) {
        _firstNameError = 'First name is required';
      } else if (_lastNameController.text.trim().isEmpty) {
        _lastNameError = 'Last name is required';
      } else if (!_emailRegex.hasMatch(_emailController.text.trim())) {
        _emailError = 'Enter a valid email address';
      } else if (_phoneController.text.replaceAll(RegExp(r'\D'), '').length < 7) {
        _phoneError = 'Enter a valid phone number';
      } else if (_passwordStrength < 4) {
        _passwordError = 'Password must be 12+ characters with mixed case and a symbol';
      } else if (_confirmPasswordController.text != _passwordController.text) {
        _confirmPasswordError = "Passwords don't match";
      }
    });
    return _firstNameError == null &&
        _lastNameError == null &&
        _emailError == null &&
        _phoneError == null &&
        _passwordError == null &&
        _confirmPasswordError == null;
  }

  void _submit() {
    if (!_validate()) return;
    ref.read(signupControllerProvider.notifier).signUp(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      phoneE164: toE164(_countryCode, _phoneController.text),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    ref.listen(signupControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        showSaToast(context, message: next.error.toString(), type: SaToastType.error);
      }
      final wasLoading = previous?.isLoading ?? false;
      if (wasLoading && !next.isLoading && !next.hasError) {
        context.go('/auth/otp');
      }
    });

    final signupState = ref.watch(signupControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Create Account', style: AppTypography.headingM.copyWith(color: onSurface))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenMarginPhone,
            AppSpacing.space4,
            AppSpacing.screenMarginPhone,
            MediaQuery.of(context).viewInsets.bottom + AppSpacing.space8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SaTextField(
                      label: 'First name',
                      controller: _firstNameController,
                      errorText: _firstNameError,
                      semanticsLabel: 'First name',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: SaTextField(
                      label: 'Last name',
                      controller: _lastNameController,
                      errorText: _lastNameError,
                      semanticsLabel: 'Last name',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              SaTextField(
                label: 'Email',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                errorText: _emailError,
                semanticsLabel: 'Email',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.space4),
              SaPhoneField(
                countryCode: _countryCode,
                controller: _phoneController,
                errorText: _phoneError,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.space4),
              SaPasswordField(
                label: 'Password',
                controller: _passwordController,
                errorText: _passwordError,
                showStrengthBar: true,
                semanticsLabel: 'Password',
                onChanged: (value) => setState(() => _passwordStrength = computePasswordStrength(value)),
              ),
              const SizedBox(height: AppSpacing.space4),
              SaTextField(
                label: 'Confirm password',
                controller: _confirmPasswordController,
                obscureText: true,
                errorText: _confirmPasswordError,
                isValid: _confirmPasswordController.text.isNotEmpty &&
                    _confirmPasswordController.text == _passwordController.text,
                semanticsLabel: 'Confirm password',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.space8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _allValid ? 1.0 : 0.4,
                child: SaButton(
                  label: 'Create Account',
                  size: SaButtonSize.lg,
                  fullWidth: true,
                  isLoading: signupState.isLoading,
                  onPressed: _submit,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              Center(
                child: Wrap(
                  children: [
                    Text('Already have an account? ', style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7))),
                    GestureDetector(
                      onTap: () => context.go('/auth/login'),
                      child: Text(
                        'Sign in',
                        style: AppTypography.bodyM.copyWith(color: AppColors.violet500, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
