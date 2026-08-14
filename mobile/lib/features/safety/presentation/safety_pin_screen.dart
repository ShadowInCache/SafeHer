import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_text_field.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../data/safety_providers.dart';

/// Create, change, or remove the Emergency Cancel PIN.
///
/// The PIN is only ever sent to the server, which stores a hash of it with
/// the same password context used for account passwords. It is never written
/// to device storage in any form.
class SafetyPinScreen extends ConsumerStatefulWidget {
  const SafetyPinScreen({super.key});

  @override
  ConsumerState<SafetyPinScreen> createState() => _SafetyPinScreenState();
}

class _SafetyPinScreenState extends ConsumerState<SafetyPinScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool isChange}) async {
    final newPin = _newController.text.trim();
    final confirm = _confirmController.text.trim();

    if (newPin.length < 4) {
      setState(() => _error = 'Use at least 4 digits');
      return;
    }
    if (newPin != confirm) {
      setState(() => _error = 'Those PINs don\'t match');
      return;
    }
    if (isChange && _currentController.text.trim().isEmpty) {
      setState(() => _error = 'Enter your current PIN to change it');
      return;
    }

    setState(() {
      _error = null;
      _busy = true;
    });

    try {
      await ref.read(safetyPinStatusNotifierProvider.notifier).setPin(
        pin: newPin,
        currentPin: isChange ? _currentController.text.trim() : null,
      );
      if (!mounted) return;
      showSaToast(
        context,
        message: isChange ? 'Safety PIN updated' : 'Safety PIN created',
        type: SaToastType.success,
      );
      context.canPop() ? context.pop() : context.go('/settings/safety');
    } catch (_) {
      if (mounted) {
        setState(() => _error = isChange ? 'Current PIN is incorrect' : "Couldn't save that PIN");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final pin = _currentController.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Enter your current PIN to remove it');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(safetyPinStatusNotifierProvider.notifier).removePin(pin);
      if (!mounted) return;
      showSaToast(context, message: 'Safety PIN removed', type: SaToastType.success);
      context.canPop() ? context.pop() : context.go('/settings/safety');
    } catch (_) {
      if (mounted) setState(() => _error = 'Current PIN is incorrect');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final statusAsync = ref.watch(safetyPinStatusNotifierProvider);
    final isSet = statusAsync.valueOrNull?.isSet ?? false;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space2,
                AppSpacing.space2,
                AppSpacing.screenMarginPhone,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/settings/safety'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      isSet ? 'Change Safety PIN' : 'Create Safety PIN',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
                children: [
                  SaCard(
                    child: Text(
                      'Your Safety PIN cancels an SOS that was triggered by mistake. '
                      'It is stored hashed on the server, never on this device — so '
                      'someone holding your unlocked phone still cannot read it.',
                      style: AppTypography.bodyM.copyWith(
                        color: onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  if (isSet) ...[
                    _PinField(label: 'Current PIN', controller: _currentController),
                    const SizedBox(height: AppSpacing.space4),
                  ],
                  _PinField(label: isSet ? 'New PIN' : 'PIN', controller: _newController),
                  const SizedBox(height: AppSpacing.space4),
                  _PinField(label: 'Confirm PIN', controller: _confirmController),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.space3),
                    Text(
                      _error!,
                      style: AppTypography.bodyS.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.space6),
                  SaButton(
                    label: isSet ? 'Update PIN' : 'Create PIN',
                    onPressed: _busy ? null : () => _save(isChange: isSet),
                    isLoading: _busy,
                    fullWidth: true,
                  ),
                  if (isSet) ...[
                    const SizedBox(height: AppSpacing.space3),
                    SaButton(
                      label: 'Remove PIN',
                      onPressed: _busy ? null : _remove,
                      variant: SaButtonVariant.danger,
                      confirmRequired: true,
                      fullWidth: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SaTextField(
      label: label,
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
    );
  }
}
