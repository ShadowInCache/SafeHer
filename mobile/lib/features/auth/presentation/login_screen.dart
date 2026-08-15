import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_password_field.dart';
import '../../../shared/components/inputs/sa_text_field.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../../../shared/utils/user_error.dart';
import 'login_controller.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String value) {
    if (value.trim().isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  void _submit() {
    final error = _validateEmail(_emailController.text);
    setState(() => _emailError = error);
    if (error != null) return;
    ref.read(loginControllerProvider.notifier).signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    ref.listen(loginControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        final failure = describeError(next.error, fallbackTitle: 'Couldn’t sign you in');
        showSaToast(
          context,
          title: failure.title,
          message: failure.message,
          type: SaToastType.error,
        );
      }
      final wasLoading = previous?.isLoading ?? false;
      if (wasLoading && !next.isLoading && !next.hasError) {
        context.go('/home');
      }
    });

    final loginState = ref.watch(loginControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Background comes from the global `SaAmbientBackground`. A per-screen
      // gradient only covered its own child -- leaving a hard seam below the
      // fold -- and hardcoded dark colours onto light mode.
      body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenMarginPhone,
              AppSpacing.space8,
              AppSpacing.screenMarginPhone,
              MediaQuery.of(context).viewInsets.bottom + AppSpacing.space8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SaIcon(SaIconGlyph.shield, size: 48, color: onSurface),
                      const SizedBox(width: AppSpacing.space2),
                      Text(
                        'SAFEHER',
                        style: AppTypography.headingL.copyWith(color: onSurface, letterSpacing: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space10),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 16, end: 0),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  builder: (context, offsetY, child) => Transform.translate(offset: Offset(0, offsetY), child: child),
                  child: Text('Welcome back', style: AppTypography.displayM.copyWith(color: onSurface)),
                ),
                const SizedBox(height: AppSpacing.space2),
                Text(
                  'Sign in to your safe space',
                  style: AppTypography.bodyL.copyWith(color: onSurface.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: AppSpacing.space8),
                SaTextField(
                  label: 'Email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  errorText: _emailError,
                  semanticsLabel: 'Email',
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                ),
                const SizedBox(height: AppSpacing.space4),
                SaPasswordField(label: 'Password', controller: _passwordController, semanticsLabel: 'Password'),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.go('/auth/forgot'),
                    child: Text('Forgot?', style: AppTypography.labelL.copyWith(color: AppColors.violet500)),
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),
                SaButton(
                  label: 'Sign In',
                  size: SaButtonSize.lg,
                  fullWidth: true,
                  isLoading: loginState.isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.space8),
                Row(
                  children: [
                    Expanded(child: Divider(color: onSurface.withValues(alpha: 0.15))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                      child: Text(
                        'or continue with',
                        style: AppTypography.bodyS.copyWith(color: AppColors.neutral400),
                      ),
                    ),
                    Expanded(child: Divider(color: onSurface.withValues(alpha: 0.15))),
                  ],
                ),
                const SizedBox(height: AppSpacing.space6),
                _SocialSignInButton(
                  label: 'Continue with Google',
                  glyph: SaIconGlyph.shield,
                  isLoading: loginState.isLoading,
                  onPressed: () => ref.read(loginControllerProvider.notifier).signInWithGoogle(),
                ),
                if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                  const SizedBox(height: AppSpacing.space3),
                  SaButton(
                    label: 'Continue with Apple',
                    variant: SaButtonVariant.secondary,
                    size: SaButtonSize.lg,
                    fullWidth: true,
                    isLoading: loginState.isLoading,
                    onPressed: () => ref.read(loginControllerProvider.notifier).signInWithApple(),
                  ),
                ],
                const SizedBox(height: AppSpacing.space5),
                // Guest mode. Deliberately the last option and styled as a
                // text button: it is a genuine escape hatch for someone who
                // needs the SOS button now, not the path we steer people to,
                // because an anonymous account cannot be recovered on a new
                // device.
                Center(
                  child: TextButton(
                    onPressed: loginState.isLoading
                        ? null
                        : () => ref.read(loginControllerProvider.notifier).signInAsGuest(),
                    child: Text(
                      'Continue as guest',
                      style: AppTypography.labelL.copyWith(
                        color: onSurface.withValues(alpha: 0.75),
                        decoration: TextDecoration.underline,
                        decorationColor: onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space5),
                Center(
                  child: Wrap(
                    children: [
                      Text(
                        'New here? ',
                        style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/auth/signup'),
                        child: Text(
                          'Create account',
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

class _SocialSignInButton extends StatelessWidget {
  const _SocialSignInButton({
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final SaIconGlyph glyph;
  final VoidCallback onPressed;

  /// Disables the button while any sign-in is in flight, so a second provider
  /// cannot be started on top of the first.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: Material(
        color: Colors.white,
        borderRadius: AppRadius.mdRadius,
        child: InkWell(
          borderRadius: AppRadius.mdRadius,
          onTap: isLoading ? null : onPressed,
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SaIcon(glyph, size: 20, color: AppColors.neutral900),
                const SizedBox(width: AppSpacing.space3),
                Text(label, style: AppTypography.labelL.copyWith(color: AppColors.neutral900)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
