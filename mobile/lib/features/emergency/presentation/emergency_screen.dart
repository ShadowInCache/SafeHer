import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../contacts/domain/models/contact.dart';
import 'widgets/emergency_cancelled_stage.dart';
import 'widgets/emergency_countdown_stage.dart';
import 'widgets/emergency_dispatched_stage.dart';
import 'widgets/emergency_pre_activation_stage.dart';

enum EmergencyStage { preActivation, countdown, dispatched, cancelled }

const _countdownSeconds = 5;

/// The 4-stage SOS flow: hold-to-confirm, a cancellable countdown, the
/// dispatched/help-is-on-the-way state (with staggered contact
/// notification), and the false-alarm "I'm safe" cancellation.
class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key});

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  EmergencyStage _stage = EmergencyStage.preActivation;
  int _secondsRemaining = _countdownSeconds;
  Timer? _countdownTimer;
  Timer? _notifyTimer;
  int _notifyIndex = 0;
  final Set<String> _notifiedContactIds = {};
  List<Contact> _contacts = const [];

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }

  void _handleSosConfirmed() {
    setState(() {
      _stage = EmergencyStage.countdown;
      _secondsRemaining = _countdownSeconds;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _stage = EmergencyStage.dispatched);
        _startNotifyingContacts();
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _stage = EmergencyStage.preActivation;
      _secondsRemaining = _countdownSeconds;
    });
  }

  void _startNotifyingContacts() {
    _contacts = ref.read(contactsNotifierProvider).valueOrNull ?? const [];
    _notifyIndex = 0;
    _notifiedContactIds.clear();
    if (_contacts.isEmpty) return;
    _notifyTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (!mounted || _notifyIndex >= _contacts.length) {
        timer.cancel();
        return;
      }
      setState(() => _notifiedContactIds.add(_contacts[_notifyIndex].id));
      _notifyIndex += 1;
    });
  }

  void _markSafe() {
    _notifyTimer?.cancel();
    setState(() => _stage = EmergencyStage.cancelled);
  }

  void _returnHome() => context.go('/home');

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsNotifierProvider);
    final canLeave = _stage == EmergencyStage.preActivation || _stage == EmergencyStage.cancelled;

    return Scaffold(
      backgroundColor: _stage == EmergencyStage.preActivation ? null : AppColors.dark900,
      body: SafeArea(
        child: Column(
          children: [
            _EmergencyHeader(visible: canLeave, onBack: _handleBack),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: switch (_stage) {
                  EmergencyStage.preActivation => EmergencyPreActivationStage(
                    key: const ValueKey('preActivation'),
                    onConfirmed: _handleSosConfirmed,
                  ),
                  EmergencyStage.countdown => EmergencyCountdownStage(
                    key: const ValueKey('countdown'),
                    secondsRemaining: _secondsRemaining,
                    totalSeconds: _countdownSeconds,
                    onCancel: _cancelCountdown,
                  ),
                  EmergencyStage.dispatched => EmergencyDispatchedStage(
                    key: const ValueKey('dispatched'),
                    contactsAsync: contactsAsync,
                    notifiedContactIds: _notifiedContactIds,
                    onMarkSafe: _markSafe,
                  ),
                  EmergencyStage.cancelled => EmergencyCancelledStage(
                    key: const ValueKey('cancelled'),
                    onReturnHome: _returnHome,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyHeader extends StatelessWidget {
  const _EmergencyHeader({required this.visible, required this.onBack});

  final bool visible;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !visible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space2, AppSpacing.space2, AppSpacing.screenMarginPhone, 0),
          child: Row(
            children: [
              IconButton(
                icon: const SaIcon(SaIconGlyph.close, color: Colors.white),
                onPressed: onBack,
                tooltip: 'Close',
              ),
              Text('Emergency', style: AppTypography.headingM.copyWith(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}
