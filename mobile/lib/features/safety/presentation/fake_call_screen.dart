import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/inputs/sa_text_field.dart';

/// Schedules a convincing incoming-call screen, to give the user a reason to
/// step away from a situation that feels wrong.
///
/// Deliberately **not** connected to the emergency system: no incident is
/// created, no contact is notified, nothing is dispatched. It is a social
/// exit, not an alert — wiring it into SOS would mean every use of it cried
/// wolf to the people the real alert depends on.
class FakeCallScreen extends StatefulWidget {
  const FakeCallScreen({super.key});

  @override
  State<FakeCallScreen> createState() => _FakeCallScreenState();
}

class _FakeCallScreenState extends State<FakeCallScreen> {
  final _nameController = TextEditingController(text: 'Mum');

  int _delaySeconds = 10;
  Timer? _pendingCall;
  int _countdown = 0;

  static const _delayOptions = [5, 10, 30, 60];

  @override
  void dispose() {
    _pendingCall?.cancel();
    _nameController.dispose();
    super.dispose();
  }

  void _schedule() {
    _pendingCall?.cancel();
    setState(() => _countdown = _delaySeconds);

    _pendingCall = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
        _ring();
      } else {
        setState(() => _countdown -= 1);
      }
    });
  }

  void _cancelSchedule() {
    _pendingCall?.cancel();
    setState(() => _countdown = 0);
  }

  Future<void> _ring() async {
    final caller = _nameController.text.trim().isEmpty ? 'Unknown' : _nameController.text.trim();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _IncomingCallScreen(callerName: caller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isScheduled = _countdown > 0;

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
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      'Fake Call',
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
                      'Schedules a realistic incoming call so you have a reason to step '
                      'away. Nothing is sent to your contacts and no alert is raised.',
                      style: AppTypography.bodyM.copyWith(
                        color: onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space5),
                  SaTextField(label: 'Caller name', controller: _nameController),
                  const SizedBox(height: AppSpacing.space5),
                  Text('Call me in', style: AppTypography.labelL.copyWith(color: onSurface)),
                  const SizedBox(height: AppSpacing.space2),
                  Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      for (final seconds in _delayOptions)
                        GestureDetector(
                          onTap: () => setState(() => _delaySeconds = seconds),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space4,
                              vertical: AppSpacing.space2,
                            ),
                            decoration: BoxDecoration(
                              color: _delaySeconds == seconds
                                  ? AppColors.violet500
                                  : onSurface.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              seconds >= 60 ? '1 min' : '${seconds}s',
                              style: AppTypography.labelM.copyWith(
                                color: _delaySeconds == seconds
                                    ? Colors.white
                                    : onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space6),
                  if (isScheduled) ...[
                    Center(
                      child: Text(
                        'Ringing in $_countdown s',
                        style: AppTypography.headingM.copyWith(color: AppColors.violet500),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    SaButton(
                      label: 'Cancel',
                      onPressed: _cancelSchedule,
                      variant: SaButtonVariant.secondary,
                      fullWidth: true,
                    ),
                  ] else
                    SaButton(label: 'Schedule fake call', onPressed: _schedule, fullWidth: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The incoming-call screen itself. Styled to read as a call, with a repeating
/// haptic pulse instead of an audio ringtone — no ringtone asset ships with
/// the app, and a silent-but-buzzing call is the safer default in the
/// situations this feature exists for.
class _IncomingCallScreen extends StatefulWidget {
  const _IncomingCallScreen({required this.callerName});

  final String callerName;

  @override
  State<_IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<_IncomingCallScreen> {
  Timer? _vibrationTimer;
  Timer? _durationTimer;
  bool _answered = false;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _startRinging();
  }

  @override
  void dispose() {
    _vibrationTimer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startRinging() {
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _answer() {
    _vibrationTimer?.cancel();
    setState(() => _answered = true);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds += 1);
    });
  }

  void _hangUp() {
    _vibrationTimer?.cancel();
    _durationTimer?.cancel();
    Navigator.of(context).pop();
  }

  String get _durationLabel {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    widget.callerName.characters.first.toUpperCase(),
                    style: AppTypography.displayM.copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space5),
              Text(
                widget.callerName,
                style: AppTypography.displayM.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                _answered ? _durationLabel : 'Incoming call…',
                style: AppTypography.bodyL.copyWith(color: Colors.white70),
              ),
              const Spacer(flex: 3),
              if (_answered)
                _CallButton(
                  label: 'End',
                  color: AppColors.danger500,
                  glyph: SaIconGlyph.close,
                  onTap: _hangUp,
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallButton(
                      label: 'Decline',
                      color: AppColors.danger500,
                      glyph: SaIconGlyph.close,
                      onTap: _hangUp,
                    ),
                    _CallButton(
                      label: 'Answer',
                      color: AppColors.success500,
                      glyph: SaIconGlyph.check,
                      onTap: _answer,
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.space6),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.label,
    required this.color,
    required this.glyph,
    required this.onTap,
  });

  final String label;
  final Color color;
  final SaIconGlyph glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(child: SaIcon(glyph, size: 28, color: Colors.white)),
            ),
            const SizedBox(height: AppSpacing.space2),
            Text(label, style: AppTypography.bodyS.copyWith(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
