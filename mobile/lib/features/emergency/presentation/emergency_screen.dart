import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/evidence/evidence_recorder.dart';
import '../../../core/network/backend_warmer.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/evidence/video_recorder.dart';
import '../../../core/local/app_preferences.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/location/location_result.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../contacts/data/contacts_providers.dart';
import '../../safety/data/safety_providers.dart';
import '../../safety/presentation/widgets/cancel_pin_prompt.dart';
import '../data/emergency_providers.dart';
import '../domain/models/evidence_state.dart';
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
  final Set<String> _notifiedContactIds = {};

  /// Null until the dispatch call comes back — the view shows contacts as
  /// still pending until then, rather than assuming either outcome.
  DispatchResult? _dispatchResult;

  EvidenceState _evidence = EvidenceState.idle;
  Timer? _recordingWindow;

  /// Resolved eagerly in [initState], not lazily: dispose() has to tear the
  /// recorder down and `ref` is unusable by then, so a `late final` that had
  /// never been touched would throw on the way out. Leaving the microphone
  /// open because teardown failed would be a live recording the user cannot
  /// see or stop.
  late final EvidenceRecorder _recorder;
  late final VideoEvidenceRecorder _videoRecorder;

  /// Whether the camera actually opened. Reported after dispatch so the
  /// user knows what was captured, never prompted for mid-emergency.
  bool _hasVideo = false;
  LocationResult? _location;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(evidenceRecorderProvider);
    _videoRecorder = ref.read(videoRecorderProvider);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleSosConfirmed();
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recordingWindow?.cancel();
    // Not awaited: dispose cannot be async, and an abandoned recording must
    // still be torn down rather than left holding the microphone.
    unawaited(_recorder.cancel());
    super.dispose();
  }

  void _handleSosConfirmed() {
    setState(() {
      _countdownSeconds = ref.read(appPreferencesProvider).countdownSeconds;
      _stage = EmergencyStage.countdown;
      _secondsRemaining = _countdownSeconds;
      _location = null;
    });
    _wakeBackend();
    _fetchLocation();
    _startRecording();
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

  /// Wakes a sleeping backend while the countdown runs.
  ///
  /// See [BackendWarmer]: the countdown is ten deliberate seconds during
  /// which nothing is sent, and spending the first of them waking a
  /// suspended instance means the alert that follows is not the request
  /// paying the spin-up.
  void _wakeBackend() => ref.read(backendWarmerProvider).warm();

  /// Evidence capture begins with the countdown, not after dispatch.
  ///
  /// FR-EMG-06 asks for recording within a second of the trigger; starting
  /// here beats that, and it means the recording covers the seconds the user
  /// spent deciding — often the most telling part. Failure is deliberately
  /// quiet: a missing microphone permission must never interrupt someone
  /// mid-emergency with a dialog. The dispatched view reports the outcome
  /// afterwards instead.
  void _startRecording() {
    unawaited(
      _recorder.start().then((_) {
        if (mounted) setState(() => _evidence = EvidenceState.recording);
      }).catchError((Object error) {
        if (!mounted) return;
        setState(() {
          _evidence = error is EvidenceRecorderException &&
                  error.reason == EvidenceRecorderFailure.unsupported
              ? EvidenceState.unsupported
              : EvidenceState.unavailable;
        });
      }),
    );
    _startVideo();
  }

  /// Video runs alongside audio, on its own failure path.
  ///
  /// Deliberately does not touch `_evidence`: that state describes the audio
  /// recording, which is the one that works wherever the phone happens to
  /// be. A phone in a pocket films a pocket, so a camera that cannot open —
  /// no permission, no lens, already in use — is an ordinary outcome and
  /// must cost nothing. It is swallowed here rather than surfaced, because
  /// there is no action the user could usefully take mid-emergency.
  void _startVideo() {
    unawaited(
      _videoRecorder.start().then((_) {
        if (mounted) setState(() => _hasVideo = true);
      }).catchError((Object _) {
        // No video this time. The alert and the audio are unaffected.
      }),
    );
  }

  /// Stops the recording and uploads it against the incident the alert just
  /// created.
  ///
  /// Runs after dispatch because the incident id does not exist until then.
  /// An offline alert has no incident yet, so the recording is discarded
  /// rather than held indefinitely — the queued alert will be re-sent
  /// without it, which is honest about what was actually captured.
  Future<void> _finishRecording(String? incidentId) async {
    // Video is settled first and independently, so that an audio path that
    // returns early below cannot strand a camera still recording.
    final video = await _finishVideo(incidentId);

    if (!_recorder.isRecording) return;

    if (incidentId == null) {
      await _recorder.cancel();
      if (mounted) setState(() => _evidence = EvidenceState.discarded);
      return;
    }

    final recording = await _recorder.stop();
    if (recording == null) {
      if (mounted) setState(() => _evidence = EvidenceState.unavailable);
      return;
    }

    if (mounted) setState(() => _evidence = EvidenceState.uploading);
    try {
      final repository = ref.read(evidenceRepositoryProvider);
      await repository.upload(incidentId: incidentId, recording: recording);
      // Audio first, then video. If the connection dies partway, the
      // recording that works regardless of where the phone was is the one
      // already on the server.
      if (video != null) {
        try {
          await repository.upload(incidentId: incidentId, recording: video);
        } catch (_) {
          // The audio is saved; a failed video upload does not undo that.
        }
      }
      if (mounted) setState(() => _evidence = EvidenceState.saved);
    } catch (_) {
      if (mounted) setState(() => _evidence = EvidenceState.uploadFailed);
    }
  }

  /// Stops video and returns it for upload, or null if there is none.
  ///
  /// A discarded alert discards the video too: an incident that was never
  /// created has nothing to attach it to, and holding footage of someone's
  /// emergency on the device is exactly what the evidence path exists to
  /// avoid.
  Future<EvidenceRecording?> _finishVideo(String? incidentId) async {
    if (!_videoRecorder.isRecording) return null;
    if (incidentId == null) {
      await _videoRecorder.cancel();
      return null;
    }
    try {
      return await _videoRecorder.stop();
    } catch (_) {
      return null;
    }
  }

  /// Not awaited by the countdown — the dispatched-stage UI appears
  /// immediately regardless of network state, so a slow request never
  /// leaves the user staring at nothing mid-emergency. The *result*,
  /// however, is now used: it decides which contacts are shown as reached.
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
          )
          .then((result) {
            if (!mounted) return;
            setState(() {
              _dispatchResult = result;
              _notifiedContactIds
                ..clear()
                ..addAll(result.outcome.reachedContactIds);
            });
            // Give the recording a moment to capture the aftermath before
            // closing it; the alert has already gone out either way.
            _recordingWindow = Timer(
              const Duration(seconds: 20),
              () => unawaited(_finishRecording(result.outcome.incidentId)),
            );
          }),
    );
  }

  /// Loads the contact list for the dispatched view.
  ///
  /// This used to walk a 600ms timer down the list, marking each contact
  /// notified as it went, with no connection to whether anything had been
  /// sent — pure animation. On this screen that is not a cosmetic problem:
  /// it told a woman in danger that her sister had been alerted when no
  /// message had left the phone. Contacts are now marked only by
  /// [_dispatchAlert], from what the server reports it actually delivered.
  void _startNotifyingContacts() {
    _notifiedContactIds.clear();
  }

  void _markSafe() {
    // A false alarm's recording is deleted, not uploaded: FR-EMG-08 says a
    // cancelled alert is logged but not transmitted.
    _recordingWindow?.cancel();
    unawaited(_recorder.cancel());
    setState(() {
      _evidence = EvidenceState.discarded;
      _stage = EmergencyStage.cancelled;
    });
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
                    dispatchResult: _dispatchResult,
                    evidence: _evidence,
                    hasVideo: _hasVideo,
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
