import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/inputs/sa_text_field.dart';
import '../../data/safety_providers.dart';

/// Blocks cancelling a live SOS until the Safety PIN is entered.
///
/// Shown only when the user turned "require PIN to cancel" on. Verification
/// happens server-side, so the correct PIN is never present on the device for
/// anyone to extract, and repeated wrong guesses are rate-limited there.
///
/// Returns true when the PIN checked out, false/null otherwise — the caller
/// keeps the countdown running unless it gets a true.
class CancelPinPrompt extends ConsumerStatefulWidget {
  const CancelPinPrompt({super.key});

  @override
  ConsumerState<CancelPinPrompt> createState() => _CancelPinPromptState();
}

class _CancelPinPromptState extends ConsumerState<CancelPinPrompt> {
  final _controller = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final pin = _controller.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your Safety PIN');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ref.read(safetyRepositoryProvider).verifyPin(pin);
      if (!mounted) return;

      if (result.valid) {
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _controller.clear();
        if (result.lockedUntil != null) {
          _error = 'Too many attempts — the alert will continue.';
        } else if (result.attemptsRemaining != null) {
          _error = 'Incorrect PIN — ${result.attemptsRemaining} attempt'
              '${result.attemptsRemaining == 1 ? '' : 's'} left.';
        } else {
          _error = 'Incorrect PIN.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't reach the server — the alert will continue.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenMarginPhone,
        right: AppSpacing.screenMarginPhone,
        top: AppSpacing.space5,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter Safety PIN', style: AppTypography.headingM.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'The countdown keeps running until the correct PIN is entered.',
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: AppSpacing.space5),
          SaTextField(
            label: 'Safety PIN',
            controller: _controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            errorText: _error,
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: AppSpacing.space5),
          SaButton(
            label: 'Cancel the alert',
            onPressed: _busy ? null : _verify,
            isLoading: _busy,
            fullWidth: true,
          ),
          const SizedBox(height: AppSpacing.space3),
          SaButton(
            label: 'Keep alert running',
            onPressed: () => Navigator.of(context).pop(false),
            variant: SaButtonVariant.secondary,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}
