import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/local/app_preferences.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/location/location_result.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../contacts/domain/models/contact.dart';
import '../../safety/data/safety_providers.dart';
import '../../safety/presentation/widgets/cancel_pin_prompt.dart';
import '../data/emergency_providers.dart';
import 'widgets/emergency_cancelled_stage.dart';
import 'widgets/emergency_countdown_stage.dart';
import 'widgets/emergency_dispatched_stage.dart';
import 'widgets/emergency_pre_activation_stage.dart';

enum EmergencyStage { preActivation, countdown, dispatched, cancelled }

// Spec default: FR-EMG-03 requires a 10-second cancellable countdown.
// Overridable in Profile > Preferences > Countdown Duration (5/10/15s);
// this is only the fallback before that preference has been read.
const _defaultCountdownSeconds = 10;

/// The 4-stage SOS flow: hold-to-confirm, a cancellable countdown, the
/// dispatched/help-is-on-the-way state (with staggered contact
/// notification), and the false-alarm "I'm safe" cancellation.
class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key, this.autoStart = false});

  /// Set when the screen was opened by a trigger that already counts as the
  /// user asking for help — the shake gesture or a voice command. The
  /// countdown starts immediately, but it is still a *countdown*: the user
  /// gets the same seconds to stand it down as a manual SOS.
  final bool autoStart;

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  EmergencyStage _stage = EmergencyStage.preActivation;
  int _countdownSeconds = _defaultCountdownSeconds;
  int _secondsRemaining = _defaultCountdownSeconds;
  Timer? _countdownTimer;
  Timer? _notifyTimer;
  int _notifyIndex = 0;
  final Set<String> _notifiedContactIds = {};
  List<Contact> _contacts = const [];
  LocationResult? _location;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleSosConfirmed();
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }

  void _handleSosConfirmed() {
    setState(() {
      _countdownSeconds = ref.read(appPreferencesProvider).countdownSeconds;
      _stage = EmergencyStage.countdown;
      _secondsRemaining = _countdownSeconds;
      _location = null;
    });
    _fetchLocation();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _stage = EmergencyStage.dispatched);
        _startNotifyingContacts();
        _dispatchAlert();
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  /// Stands the countdown down. When the user has turned on "require PIN to
  /// cancel", the PIN must be verified server-side first — and crucially the
  /// countdown keeps running while the prompt is open, so stalling at the PIN
  /// screen cannot itself defeat the alert.
  Future<void> _cancelCountdown() async {
    // Awaited, not read: a preference that simply hadn't finished loading
    // would otherwise read as "no PIN required" and silently skip the gate.
    bool requiresPin;
    try {
      requiresPin = (await ref.read(safetyPreferencesNotifierProvider.future)).requirePinToCancel;
    } catch (_) {
      // Preferences unreachable. Don't trap the user behind a gate we can't
      // verify — an unverifiable PIN check would make cancelling impossible.
      requiresPin = false;
    }
    if (!mounted) return;

    if (!requiresPin) {
      _stopCountdown();
      return;
    }

    // Dismissing the sheet returns null, which reads as "don't cancel" — the
    // safe default for a live alert.
    final verified = await showSaBottomSheet<bool>(
      context,
      builder: (context) => const CancelPinPrompt(),
    );

    if (!mounted) return;
    // The countdown may have completed and dispatched while the prompt was
    // open — in that case there is nothing left to cancel here.
    if (verified == true && _stage == EmergencyStage.countdown) _stopCountdown();
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _stage = EmergencyStage.preActivation;
      _secondsRemaining = _countdownSeconds;
    });
  }

  /// Kicked off the moment the countdown starts, not awaited by it — a
  /// weak/no GPS signal must never delay or block the SOS countdown itself.
  /// Whatever fix (or lack of one) has arrived by the time the countdown
  /// completes is what gets attached to the dispatch in [_dispatchAlert].
  void _fetchLocation() {
    unawaited(
      ref.read(locationServiceProvider).getCurrentLocation().then((result) {
        if (mounted) setState(() => _location = result);
      }),
    );
  }

  /// Fire-and-forget: the dispatched-stage UI (contact notification,
  /// evidence sharing) shows immediately regardless of network state, so
  /// this doesn't block anything on screen. If offline it queues via
  /// [EmergencyDispatchNotifier] and replays automatically on reconnect —
  /// see that provider for why the UI doesn't need to know the difference.
  void _dispatchAlert() {
    final location = _location;
    final hasFix = location is LocationAvailable;
    unawaited(
      ref
          .read(emergencyDispatchNotifierProvider.notifier)
          .dispatch(
            severity: 'critical',
            summary: 'Emergency SOS triggered',
            auto: false,
            latitude: hasFix ? location.latitude : null,
            longitude: hasFix ? location.longitude : null,
            accuracyMeters: hasFix ? location.accuracyMeters : null,
          ),
    );
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
    // Warms the preference so the cancel gate resolves instantly rather than
    // making the user wait on a network round-trip mid-countdown.
    ref.watch(safetyPreferencesNotifierProvider);
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
                    location: _location,
                  ),
                  EmergencyStage.dispatched => EmergencyDispatchedStage(
                    key: const ValueKey('dispatched'),
                    contactsAsync: contactsAsync,
                    notifiedContactIds: _notifiedContactIds,
                    onMarkSafe: _markSafe,
                    location: _location,
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
