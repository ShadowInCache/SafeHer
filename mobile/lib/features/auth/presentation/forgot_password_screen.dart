import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_text_field.dart';
import 'forgot_password_controller.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// No detailed design spec was provided for this screen (the build sequence
/// names it but the screen-by-screen spec jumps from OTP straight to Home),
/// so its layout follows the same visual language as Login/Signup.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  String? _emailError;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final error = email.isEmpty
        ? 'Email is required'
        : (!_emailRegex.hasMatch(email) ? 'Enter a valid email address' : null);
    setState(() => _emailError = error);
    if (error != null) return;
    ref.read(forgotPasswordControllerProvider.notifier).sendResetEmail(email);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    ref.listen(forgotPasswordControllerProvider, (previous, next) {
      final wasLoading = previous?.isLoading ?? false;
      if (wasLoading && !next.isLoading && !next.hasError) {
        setState(() => _sent = true);
      }
    });

    final state = ref.watch(forgotPasswordControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.dark900,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const SaIcon(SaIconGlyph.chevronLeft, color: Colors.white),
          onPressed: () => context.go('/auth/login'),
          tooltip: 'Back',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          child: _sent ? _buildConfirmation(context) : _buildForm(context, onSurface, state.isLoading),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Color onSurface, bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Reset your password', style: AppTypography.displayM.copyWith(color: Colors.white)),
        const SizedBox(height: AppSpacing.space2),
        Text(
          "Enter your email and we'll send you a link to reset your password.",
          style: AppTypography.bodyL.copyWith(color: Colors.white.withValues(alpha: 0.7)),
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
        const SizedBox(height: AppSpacing.space6),
        SaButton(
          label: 'Send Reset Link',
          size: SaButtonSize.lg,
          fullWidth: true,
          isLoading: isLoading,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _buildConfirmation(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.success500),
          child: const SaIcon(SaIconGlyph.check, size: 32, color: Colors.white),
        ),
        const SizedBox(height: AppSpacing.space6),
        Text('Check your email', style: AppTypography.displayM.copyWith(color: Colors.white), textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.space2),
        Text(
          "We've sent a password reset link to ${_emailController.text.trim()}.",
          textAlign: TextAlign.center,
          style: AppTypography.bodyL.copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: AppSpacing.space8),
        SaButton(
          label: 'Back to Sign In',
          size: SaButtonSize.lg,
          fullWidth: true,
          onPressed: () => context.go('/auth/login'),
        ),
      ],
    );
  }
}
