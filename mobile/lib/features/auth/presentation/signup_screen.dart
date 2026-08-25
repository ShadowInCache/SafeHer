import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_providers.dart';
import '../../../core/session/session_reset.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_password_field.dart';
import '../../../shared/components/inputs/sa_phone_field.dart';
import '../../../shared/components/inputs/sa_text_field.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../../shared/utils/user_error.dart';
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
  late final _termsTapRecognizer = TapGestureRecognizer()
    ..onTap = () => showSaToast(context, message: 'Terms of Service — coming soon.');
  late final _privacyTapRecognizer = TapGestureRecognizer()
    ..onTap = () => showSaToast(context, message: 'Privacy Policy — coming soon.');

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
    _termsTapRecognizer.dispose();
    _privacyTapRecognizer.dispose();
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

  Future<void> _routeAfterSignUp() async {
    final signedIn = await ref.read(authRepositoryProvider).hasActiveSession();
    if (!mounted) return;
    if (signedIn) {
      // A session starts here as surely as it does on the sign-in screen, and
      // this path did not clear the previous account's cached state. Sign out,
      // sign *up* as somebody else, and the last account's emergency contacts
      // were still in memory -- their names and phone numbers, on the new
      // account's home screen.
      resetSessionScopedState(ref);
      context.go('/home');
    } else {
      context.go('/auth/otp', extra: toE164(_countryCode, _phoneController.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    ref.listen(signupControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final failure = describeError(next.error, fallbackTitle: 'Couldn’t create your account');
        showSaToast(
          context,
          title: failure.title,
          message: failure.message,
          type: SaToastType.error,
        );
      }
      final wasLoading = previous?.isLoading ?? false;
      if (wasLoading && !next.isLoading && !next.hasError) {
        // Sign-up either establishes a session outright or leaves the account
        // pending a verification code. Routing to the OTP screen in the first
        // case would strand the user waiting for a code that is never sent, so
        // the presence of a session decides where to go.
        unawaited(_routeAfterSignUp());
      }
    });

    final signupState = ref.watch(signupControllerProvider);

    return Scaffold(
      // The bar keeps its automatic leading -- that back button is the only
      // way out of this screen -- but gives up its title, because the header
      // below says the same thing with room to breathe.
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
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
              Text(
                'GET STARTED',
                semanticsLabel: 'Get started',
                style: AppTypography.eyebrow.copyWith(color: context.saColors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'Create your account',
                style: AppTypography.displayCondensed.copyWith(color: onSurface, fontSize: 40),
              ),
              const SizedBox(height: AppSpacing.space5),
              Container(height: 1, color: context.saColors.line),
              const SizedBox(height: AppSpacing.space6),
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
                // Live mismatch indicator (red X) while the user is still
                // typing, distinct from the full errorText treatment which
                // only appears after a submit attempt.
                suffixIcon: _confirmPasswordController.text.isNotEmpty &&
                        _confirmPasswordController.text != _passwordController.text &&
                        _confirmPasswordError == null
                    ? const SaIcon(SaIconGlyph.close, size: 18, color: AppColors.coral500)
                    : null,
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
                child: Text.rich(
                  TextSpan(
                    style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                    children: [
                      const TextSpan(text: 'By continuing you agree to our '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: AppTypography.bodyS.copyWith(color: context.saColors.interactive, fontWeight: FontWeight.w600),
                        recognizer: _termsTapRecognizer,
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: AppTypography.bodyS.copyWith(color: context.saColors.interactive, fontWeight: FontWeight.w600),
                        recognizer: _privacyTapRecognizer,
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              Center(
                child: Wrap(
                  children: [
                    Text('Already have an account? ', style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7))),
                    Semantics(
                      button: true,
                      label: 'Sign in',
                      child: GestureDetector(
                        onTap: () => context.go('/auth/login'),
                        child: Text(
                          'Sign in',
                          style: AppTypography.bodyM.copyWith(color: context.saColors.interactive, fontWeight: FontWeight.w600),
                        ),
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
