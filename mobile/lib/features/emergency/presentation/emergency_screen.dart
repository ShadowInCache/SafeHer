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
import '../../../core/theme/theme_extensions.dart';
import '../../devices/data/glasses_providers.dart';
import '../../devices/data/glasses_dio.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/utils/random_id.dart';
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
import '../../../core/audio/microphone_arbiter.dart';
import '../../devices/data/glasses_pairing_controller.dart';
import '../../devices/data/glasses_audio_recorder.dart';

enum EmergencyStage { preActivation, countdown, dispatched, cancelled }

// The fallback used before the countdown preference has been read. It takes
// its value from the same constant the preference defaults to, so the two can
// no longer disagree -- see [kDefaultCountdownSeconds] for why it is 5 and
// not the SRS's 10.
const _defaultCountdownSeconds = kDefaultCountdownSeconds;

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

  /// Chosen on this device before the request goes out, so a retry after a
  /// timeout resolves to the same incident instead of filing a second
  /// emergency and messaging every contact twice. It also means the recording
  /// has something to be filed against even when the alert had to be queued.
  String? _incidentId;

  /// Polls the server for the fan-out result while the dispatched stage is
  /// on screen. The server answers the SOS before it has finished contacting
  /// anyone — see [EmergencyRepository] — so this is how "Sending…" ever
  /// becomes an answer.
  Timer? _statusPoll;

  /// Resolved eagerly in [initState], not lazily: dispose() has to tear the
  /// recorder down and `ref` is unusable by then, so a `late final` that had
  /// never been touched would throw on the way out. Leaving the microphone
  /// open because teardown failed would be a live recording the user cannot
  /// see or stop.
  late final EvidenceRecorder _recorder;
  late final VideoEvidenceRecorder _videoRecorder;

  /// Resolved eagerly for the same reason, and it matters more here: dispose()
  /// has to hand the microphone back, and reading `ref` by then throws. If that
  /// throw escaped, threat listening would never resume for the rest of the
  /// journey — leaving the screen would silently cost a signal.
  late final MicrophoneArbiter _microphone;

  /// Records the glasses' microphone, when a pair is connected.
  ///
  /// Null whenever no camera is paired, which is the ordinary case — the
  /// recorder is built at trigger time from the saved address rather than held
  /// open for a journey that may never need it.
  GlassesAudioRecorder? _glassesAudio;

  /// Whether the camera actually opened. Reported after dispatch so the
  /// user knows what was captured, never prompted for mid-emergency.
  bool _hasVideo = false;

  /// Whether the glasses' stream actually opened. Reported after dispatch,
  /// never prompted for mid-emergency.
  bool _hasGlassesAudio = false;
  LocationResult? _location;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(evidenceRecorderProvider);
    _videoRecorder = ref.read(videoRecorderProvider);
    _microphone = ref.read(microphoneArbiterProvider.notifier);
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
    _statusPoll?.cancel();
    // Not awaited: dispose cannot be async, and an abandoned recording must
    // still be torn down rather than left holding the microphone.
    unawaited(_recorder.cancel());
    unawaited(_glassesAudio?.cancel() ?? Future<void>.value());
    // And the arbiter must be told, or threat listening never resumes for the
    // rest of the journey — leaving the screen would silently cost a signal.
    //
    // Deferred by a microtask because Riverpod forbids modifying a provider
    // inside a lifecycle method: doing it directly here throws "Tried to
    // modify a provider while the widget tree was building". The notifier is
    // held rather than read, so this still works after `ref` is unusable.
    final microphone = _microphone;
    Future.microtask(microphone.releaseEvidence);
    super.dispose();
  }

  void _handleSosConfirmed() {
    setState(() {
      _countdownSeconds = ref.read(appPreferencesProvider).countdownSeconds;
      _stage = EmergencyStage.countdown;
      _secondsRemaining = _countdownSeconds;
      _location = null;
      // One id per activation, minted before anything is sent. A cancelled
      // countdown never uses it; the next activation gets a new one, so two
      // separate emergencies are never merged into one incident.
      _incidentId = newUuidV4();
      _dispatchResult = null;
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
  /// Hands the microphone back so threat listening can resume.
  ///
  /// Safe to call more than once — the arbiter ignores a release from a use
  /// that no longer holds it.
  void _releaseMicrophone() => _microphone.releaseEvidence();

  void _startRecording() {
    // Claimed before the recorder asks the platform for the device, so the
    // threat monitor has already let go by the time this runs. Both used to
    // hold it at once: on Android `SpeechRecognizer` and `record` contend for
    // the same hardware, and whichever lost, lost silently -- possibly the
    // recording, during an actual emergency.
    _microphone.claimForEvidence();

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
    _startGlassesAudio();
  }

  /// Video runs alongside audio, on its own failure path.
  ///
  /// Deliberately does not touch `_evidence`: that state describes the audio
  /// recording, which is the one that works wherever the phone happens to
  /// be. A phone in a pocket films a pocket, so a camera that cannot open —
  /// no permission, no lens, already in use — is an ordinary outcome and
  /// must cost nothing. It is swallowed here rather than surfaced, because
  /// there is no action the user could usefully take mid-emergency.
  /// Records the glasses' microphone alongside everything else.
  ///
  /// Its own failure path, and deliberately silent. A pair of glasses out of
  /// range, switched off, or never paired is the ordinary case, and there is
  /// nothing the user could usefully do about it mid-emergency.
  ///
  /// Unlike the phone recorder this needs no microphone permission and takes
  /// nothing from `MicrophoneArbiter` — it is a network socket, so it runs
  /// alongside both the phone recording and threat listening without
  /// contending for the device.
  void _startGlassesAudio() {
    final uri = ref.read(glassesPairingProvider.notifier).audioUri;
    if (uri == null) return;

    final recorder = GlassesAudioRecorder(
      streamUri: uri,
      dio: glassesDio(resolver: ref.read(glassesResolverProvider)),
    );
    _glassesAudio = recorder;
    unawaited(
      recorder.start().then((started) {
        if (mounted && started) setState(() => _hasGlassesAudio = true);
      }).catchError((Object _) {}),
    );
  }

  /// Stops the glasses recording and returns it for upload, or null.
  ///
  /// A discarded alert discards this too, for the same reason it discards the
  /// video: an incident that was never created has nothing to attach it to,
  /// and keeping a recording of someone's emergency on the device is exactly
  /// what the evidence path exists to avoid.
  Future<EvidenceRecording?> _finishGlassesAudio(String? incidentId) async {
    final recorder = _glassesAudio;
    _glassesAudio = null;
    if (recorder == null) return null;
    if (incidentId == null) {
      await recorder.cancel();
      return null;
    }
    try {
      return await recorder.stop();
    } catch (_) {
      return null;
    }
  }

  void _startVideo() {
    unawaited(
      _videoRecorder.start().then((_) {
        if (mounted) setState(() => _hasVideo = true);
      }).catchError((Object _) {
        // No video this time. The alert and the audio are unaffected.
      }),
    );
  }

  /// Stops the recording and uploads it against the incident.
  ///
  /// The incident id is chosen on this device before the alert is sent, so
  /// there is always something to file against — including when the alert
  /// itself had to be queued. That is the fix for a real defect: the previous
  /// version discarded the recording outright whenever dispatch did not
  /// return an id, which meant the emergencies that went *worst* — the ones
  /// where the network failed — were also the only ones that lost their
  /// evidence.
  ///
  /// A queued alert has no incident on the server *yet*, so the first upload
  /// will fail. [_uploadWithRetry] waits for the queue to drain rather than
  /// giving up on the first attempt.
  Future<void> _finishRecording(String? incidentId) async {
    // Video is settled first and independently, so that an audio path that
    // returns early below cannot strand a camera still recording.
    final video = await _finishVideo(incidentId);
    final glassesAudio = await _finishGlassesAudio(incidentId);

    if (!_recorder.isRecording) return;

    if (incidentId == null) {
      await _recorder.cancel();
      _releaseMicrophone();
      if (mounted) setState(() => _evidence = EvidenceState.discarded);
      return;
    }

    final recording = await _recorder.stop();
    // Released as soon as the device is genuinely free, not when the upload
    // finishes: threat listening should resume while the file is still going
    // up, because the journey may well continue afterwards.
    _releaseMicrophone();
    if (recording == null) {
      if (mounted) setState(() => _evidence = EvidenceState.unavailable);
      return;
    }

    if (mounted) setState(() => _evidence = EvidenceState.uploading);

    final saved = await _uploadWithRetry(
      incidentId: incidentId,
      recording: recording,
      // Only a queued alert is worth waiting on: its incident does not exist
      // server-side until the queue drains, so early failures are expected
      // rather than final.
      alertWasQueued: _dispatchResult?.isQueued ?? false,
    );
    if (!saved) {
      if (mounted) setState(() => _evidence = EvidenceState.uploadFailed);
      return;
    }

    // Audio first, then video. If the connection dies partway, the
    // recording that works regardless of where the phone was is the one
    // already on the server.
    // The glasses recording goes up after the phone's, for the same reason
    // video does: the phone's microphone is the one recording guaranteed to
    // exist, so it is the one that must reach the server first. This is a
    // second vantage point, not a replacement.
    if (glassesAudio != null) {
      try {
        await ref
            .read(evidenceRepositoryProvider)
            .upload(incidentId: incidentId, recording: glassesAudio);
      } catch (_) {
        // Not surfaced. Reporting "evidence not uploaded" because the glasses
        // leg failed would misdescribe a phone recording that is safely
        // stored, and there is nothing the user could do about it either way.
      }
    }

    if (video != null) {
      // Not retried as hard as the audio and its failure is not surfaced:
      // video is a bonus when the lens happened to be pointed at something,
      // and reporting "evidence not uploaded" because the video leg failed
      // would misdescribe an audio recording that is safely stored.
      try {
        await ref
            .read(evidenceRepositoryProvider)
            .upload(incidentId: incidentId, recording: video);
      } catch (_) {
        // The audio is saved; a failed video upload does not undo that.
      }
    }

    if (mounted) setState(() => _evidence = EvidenceState.saved);
  }

  /// Uploads the recording, waiting out an incident that does not exist yet.
  ///
  /// Retries only when [alertWasQueued]. That is the one case where an early
  /// failure means nothing: the incident is created server-side only once the
  /// queued alert drains, so the first attempts are expected to 404.
  ///
  /// Every other failure is reported immediately. Grinding through two
  /// minutes of retries on a recording the server has actually rejected —
  /// too large, wrong type, session expired — would leave "Saving evidence
  /// securely…" on screen long after the answer was known, and the user is
  /// reading that line to decide whether she has a recording or not.
  ///
  /// **The bytes are deliberately not persisted to disk between attempts.**
  /// [EvidenceRecording] holds them in memory precisely so no recording of an
  /// assault is left in the device's temp directory, where it is one
  /// file-manager app away from the person it was recorded about. Surviving
  /// the app being killed is not worth reintroducing that, so a recording
  /// that cannot be uploaded within the window is reported as lost rather
  /// than quietly written somewhere.
  Future<bool> _uploadWithRetry({
    required String incidentId,
    required EvidenceRecording recording,
    required bool alertWasQueued,
  }) async {
    final repository = ref.read(evidenceRepositoryProvider);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    var delay = const Duration(seconds: 3);

    while (mounted) {
      try {
        await repository.upload(incidentId: incidentId, recording: recording);
        return true;
      } catch (_) {
        if (!alertWasQueued) return false;
        if (DateTime.now().isAfter(deadline)) return false;
        await Future<void>.delayed(delay);
        // Backs off to a cap rather than growing without bound — the window
        // is short, and a long sleep at the end of it would waste it.
        delay = delay * 2 > const Duration(seconds: 20)
            ? const Duration(seconds: 20)
            : delay * 2;
      }
    }
    return false;
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
    final incidentId = _incidentId!;
    unawaited(
      ref
          .read(emergencyDispatchNotifierProvider.notifier)
          .dispatch(
            severity: 'critical',
            summary: 'Emergency SOS triggered',
            auto: false,
            incidentId: incidentId,
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

            // The server answers before it has finished contacting anyone,
            // so keep asking until it says it is done.
            if (!result.isQueued && !result.outcome.progress.isSettled) {
              _startPollingStatus(incidentId);
            }

            // Give the recording a moment to capture the aftermath before
            // closing it; the alert has already gone out either way.
            //
            // The id is passed even when the alert was queued: it was chosen
            // on this device, so the recording can still be filed against it
            // once the queued alert replays. Discarding evidence because the
            // network hiccupped threw away exactly the emergencies that went
            // worst.
            _recordingWindow = Timer(
              const Duration(seconds: 20),
              () => unawaited(_finishRecording(incidentId)),
            );
          }),
    );
  }

  /// Asks the server how the fan-out is going until it has finished.
  ///
  /// Two seconds is a compromise: fast enough that the screen stops saying
  /// "Sending…" soon after the truth is known, slow enough not to hammer a
  /// free-tier instance that is already busy sending the alert. It gives up
  /// after two minutes — past that the fan-out has either finished or died,
  /// and a spinner that never resolves is its own kind of lie.
  void _startPollingStatus(String incidentId) {
    _statusPoll?.cancel();
    final startedAt = DateTime.now();
    _statusPoll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (DateTime.now().difference(startedAt) > const Duration(minutes: 2)) {
        timer.cancel();
        return;
      }

      final outcome = await ref
          .read(emergencyDispatchNotifierProvider.notifier)
          .pollStatus(incidentId);
      // Null means the poll itself failed. Leave the last known state alone
      // rather than blanking a contact list someone is watching.
      if (outcome == null || !mounted) return;

      setState(() {
        _dispatchResult = DispatchResult.sent(outcome);
        _notifiedContactIds
          ..clear()
          ..addAll(outcome.reachedContactIds);
      });
      if (outcome.progress.isSettled) timer.cancel();
    });
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
    _statusPoll?.cancel();
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
      // Dispatched is the alert register: the whole field turns over. The
      // countdown and cancelled stages stay on the ordinary night ground —
      // one is still cancellable and the other is a resolution, so neither
      // should shout the way a sent alert does.
      backgroundColor: switch (_stage) {
        EmergencyStage.preActivation => null,
        EmergencyStage.dispatched => AppColors.emergencyField,
        _ => AppColors.dark900,
      },
      body: SafeArea(
        child: Column(
          children: [
            // The header's ink comes off the same switch as the scaffold's
            // ground, because it shows over two different ones: the theme
            // ground before activation, and dark900 once an alert has been
            // cancelled. It was pinned to white, which was correct back when
            // every stage of this screen was near-black -- and invisible on
            // the stone ground the light theme now paints behind it.
            _EmergencyHeader(
              visible: canLeave,
              onBack: _handleBack,
              ink: _stage == EmergencyStage.preActivation ? context.saColors.ink : AppColors.neutral100,
            ),
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
                    hasGlassesAudio: _hasGlassesAudio,
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
  const _EmergencyHeader({required this.visible, required this.onBack, required this.ink});

  final bool visible;
  final VoidCallback onBack;
  final Color ink;

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
                icon: SaIcon(SaIconGlyph.close, color: ink),
                onPressed: onBack,
                tooltip: 'Close',
              ),
              Text('Emergency', style: AppTypography.headingM.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}
