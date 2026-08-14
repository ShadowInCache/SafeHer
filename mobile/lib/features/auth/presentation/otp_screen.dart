import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/inputs/sa_otp_field.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../data/auth_providers.dart';
import 'otp_controller.dart';

/// Verifies the 6-digit code sent after signup. Expects the contact string
/// (phone/email) to display via GoRouterState.extra; falls back to a
/// generic message when navigated to directly (e.g. deep link, tests).
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  SaOTPFieldStatus _status = SaOTPFieldStatus.idle;
  Timer? _resendTimer;
  Timer? _errorResetTimer;
  int _secondsRemaining = 60;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _secondsRemaining = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _errorResetTimer?.cancel();
    super.dispose();
  }

  void _handleCompleted(String code) {
    ref.read(otpControllerProvider.notifier).verify(code);
  }

  Future<void> _handleResend() async {
    await ref.read(otpControllerProvider.notifier).resend();
    if (!mounted) return;
    showSaToast(context, message: 'OTP sent!', type: SaToastType.success);
    _startResendCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final contact = GoRouterState.of(context).extra as String?;

    ref.listen(otpControllerProvider, (previous, next) {
      if (next.hasError && !next.isLoading) {
        setState(() => _status = SaOTPFieldStatus.error);
        _errorResetTimer?.cancel();
        _errorResetTimer = Timer(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _status = SaOTPFieldStatus.idle);
        });
      }
      final wasLoading = previous?.isLoading ?? false;
      if (wasLoading && !next.isLoading && !next.hasError) {
        setState(() => _status = SaOTPFieldStatus.success);
        Timer(const Duration(milliseconds: 400), () {
          if (mounted) context.go('/home');
        });
      }
    });

    final otpState = ref.watch(otpControllerProvider);
    final phoneVerificationUnavailable =
        ref.watch(authRepositoryProvider).phoneVerificationUnavailable;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Verify your number', style: AppTypography.displayM.copyWith(color: onSurface)),
              const SizedBox(height: AppSpacing.space2),
              Text(
                contact != null ? 'Enter the 6-digit code sent to $contact' : 'Enter the 6-digit code we sent you',
                style: AppTypography.bodyL.copyWith(color: onSurface.withValues(alpha: 0.7)),
              ),
              // Sign-up succeeded but no code could be sent. Say so, and offer
              // the way forward — the account is already usable, so stranding
              // the user on a code that will never arrive would be the worst
              // possible outcome here.
              if (phoneVerificationUnavailable) ...[
                const SizedBox(height: AppSpacing.space4),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.space4),
                  decoration: BoxDecoration(
                    color: AppColors.warning500.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "We couldn't send a code",
                        style: AppTypography.labelL.copyWith(color: onSurface),
                      ),
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        'Phone verification is unavailable for this build. Your account '
                        'is already active, so you can continue without it.',
                        style: AppTypography.bodyS.copyWith(
                          color: onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.space3),
                      SaButton(
                        label: 'Continue to SafeHer',
                        onPressed: () => context.go('/home'),
                        size: SaButtonSize.sm,
                        fullWidth: true,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.space8),
              SaOTPField(status: _status, onCompleted: _handleCompleted),
              const SizedBox(height: AppSpacing.space6),
              if (otpState.isLoading)
                const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.violet500),
                  ),
                ),
              const SizedBox(height: AppSpacing.space4),
              Center(
                child: _secondsRemaining > 0
                    ? Text(
                        'Resend OTP in ${_secondsRemaining}s',
                        style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.5)),
                      )
                    : Semantics(
                        button: true,
                        label: 'Resend OTP',
                        child: GestureDetector(
                          onTap: _handleResend,
                          child: Text(
                            'Resend OTP',
                            style: AppTypography.bodyM.copyWith(color: AppColors.violet500, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
