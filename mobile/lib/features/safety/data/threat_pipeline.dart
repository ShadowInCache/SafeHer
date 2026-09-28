import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audio/audio_threat_monitor.dart';
import '../../../core/audio/microphone_arbiter.dart';
import '../../../core/audio/threat_phrase_classifier.dart';
import '../../../core/background/safety_foreground_service.dart';
import '../../../core/background/safety_watch.dart';
import '../../../core/local/app_preferences.dart';
import '../../devices/data/glasses_dio.dart';
import '../../devices/data/glasses_preview_providers.dart';
import '../../devices/data/glasses_providers.dart';
import '../../../core/network/network_providers.dart';
import '../../devices/data/glove_link_providers.dart';
import '../../devices/data/mjpeg_client.dart';
import '../../devices/data/remote_weapon_detector.dart';
import '../../devices/data/ultralytics_weapon_detector.dart';
import '../../devices/data/weapon_detection_service.dart';
import '../../../shared/models/threat_level.dart';
import '../../devices/domain/glove_protocol.dart';
import '../domain/camera_activation_policy.dart';
import 'safety_providers.dart';
import 'threat_signal_aggregator.dart';

part 'threat_pipeline.g.dart';

/// The phrase classifier, loaded once from assets.
@Riverpod(keepAlive: true)
Future<ThreatPhraseClassifier> threatPhraseClassifier(Ref ref) =>
    ThreatPhraseClassifier.load();

@Riverpod(keepAlive: true)
ThreatSignalAggregator threatSignalAggregator(Ref ref) {
  final aggregator = ThreatSignalAggregator(
    apiClient: ref.watch(apiClientProvider),
  );
  ref.onDispose(aggregator.dispose);
  return aggregator;
}

/// Whether continuous detection is allowed to run right now.
///
/// Tied to a journey rather than to a switch of its own. The microphone and
/// the camera are the two most intrusive things this app can touch, and
/// "while she told us she is travelling" is a boundary she set herself — a
/// standing permission to listen would be a different product.
@Riverpod(keepAlive: true)
bool threatPipelineArmed(Ref ref) {
  final journey = ref.watch(activeJourneyNotifierProvider).valueOrNull;
  return journey?.isInProgress ?? false;
}

/// What the pipeline is currently doing, readable without starting it.
///
/// **Why this exists separately from [ThreatPipeline].** The Profile screen
/// shows a line describing what can raise an alarm right now, and reading the
/// pipeline directly to find out made rendering that line *construct* the
/// pipeline — which opens the microphone. A settings screen must not be able
/// to start listening by being drawn.
///
/// So the pipeline writes here and the UI reads here. This provider has no
/// dependencies, defaults to "nothing is running", and can be watched by
/// anything at any time without side effects.
@Riverpod(keepAlive: true)
class JourneyDetectionStatus extends _$JourneyDetectionStatus {
  @override
  ThreatPipelineStatus build() => const ThreatPipelineStatus();

  void publish(ThreatPipelineStatus status) => state = status;
}

/// Starts and stops the three signals together, and feeds their scores out.
///
/// ## Why this is a provider and not a widget
///
/// The same reason `GloveAutoTrigger` is. Detection has to keep running with
/// the screen off — a phone in a pocket is the case the whole feature exists
/// for — and `build()` stops being called the moment Flutter stops pumping
/// frames. Everything here hangs off `ref.listen`, which is driven by provider
/// state rather than by the frame pipeline.
///
/// ## What it does not do
///
/// It does not decide anything. Each signal is reported to the aggregator,
/// which sends all three to the server, where `threat_fusion` weighs them
/// together and applies the threshold, the hysteresis and the dedup. No single
/// signal here can raise an alarm on its own, and that is the design: a
/// frightened sentence, a knife-shaped reflection and a dropped bag are each
/// wrong often enough that acting on one alone would train users to ignore it.
@Riverpod(keepAlive: true)
class ThreatPipeline extends _$ThreatPipeline {
  AudioThreatMonitor? _audio;
  GlassesVideoStream? _video;
  WeaponDetectionService? _weapons;

  StreamSubscription<AudioThreatReading>? _audioSub;
  StreamSubscription<GlassesStreamStatus>? _videoStatusSub;
  StreamSubscription<Object>? _weaponSub;

  /// Decides when the camera is worth opening. The microphone and the glove
  /// run for the whole journey because they are cheap; the camera is not, so
  /// it stays shut until one of them says something is happening.
  final _policy = CameraActivationPolicy();

  /// The policy is passive — it answers questions rather than firing events —
  /// so something has to ask whether the dwell has elapsed.
  Timer? _cameraTimer;

  /// Keeps this process alive while a journey is armed.
  ///
  /// Resolved once and held rather than read where it is used: `_stop` runs
  /// from `ref.onDispose`, and `ref.read` throws once disposal has begun.
  late final SafetyWatch _watch;

  @override
  ThreatPipelineStatus build() {
    _watch = ref.read(safetyWatchProvider.notifier);

    ref.listen<bool>(threatPipelineArmedProvider, (previous, armed) {
      unawaited(armed ? _start() : _stop());
    });

    // The glove reports through the same aggregator, so a fall is corroborated
    // by what the camera and the microphone saw at the same moment. Its direct
    // BLE-to-SOS path in `GloveAutoTrigger` is deliberately left alone: that
    // one works with no server and no glasses, and it must keep doing so.
    ref.listen<GloveLinkState>(gloveLinkProvider, (previous, next) {
      final classification = next.classification;
      if (classification == null || !next.isListening) return;
      final score = gloveScore(classification);
      ref.read(threatSignalAggregatorProvider).reportGlove(
            score,
            label: classification.label,
          );
      // A fall, or force applied by someone else, is reason enough to look.
      if (state.armed && _policy.reportGlove(score, now: DateTime.now())) {
        _openCameraIfNeeded();
      }
    });

    // Evidence recording outranks threat listening for the microphone. The
    // platform hands it to one caller at a time, and the emergency screen
    // starts recording the instant a countdown begins -- so the monitor has to
    // be off the device by then, not competing with it.
    ref.listen<MicrophoneUse>(microphoneArbiterProvider, (previous, use) {
      if (use == MicrophoneUse.evidence) {
        unawaited(_releaseMicrophone());
      } else if (use == MicrophoneUse.idle && state.armed && _audio == null) {
        unawaited(_guarded('audio', () => _startAudio(
              ref.read(threatSignalAggregatorProvider),
            )));
      }
    });

    ref.onDispose(() => unawaited(_stop()));
    return const ThreatPipelineStatus();
  }

  /// Maps a glove class onto the 0–1 scale the fusion engine reads.
  ///
  /// The weights follow `GloveClassification.threatLevel`, which is already a
  /// deliberately conservative product decision: only `FALL` is danger, force
  /// applied by someone else is elevated, and the movements that happen all day
  /// — a bag lifted, a hand dried — stay low. Confidence scales the result, so
  /// an unsure `FALL` is not the same claim as a certain one.
  @visibleForTesting
  static double gloveScore(GloveClassification classification) {
    final weight = switch (classification.threatLevel) {
      ThreatLevel.danger => 1.0,
      ThreatLevel.elevated => 0.7,
      ThreatLevel.caution => 0.3,
      ThreatLevel.safe => 0.0,
    };
    return (weight * classification.confidence).clamp(0.0, 1.0);
  }

  Future<void> _start() async {
    // The one step both signals genuinely depend on, so it is guarded too.
    // It sat outside the isolation below and threw into an unawaited future:
    // if the aggregator could not be built, all three signals died at once
    // and nothing recorded why. Nothing can be reported without it, so the
    // honest outcome is an unarmed pipeline that says so.
    final ThreatSignalAggregator aggregator;
    try {
      aggregator = ref.read(threatSignalAggregatorProvider)..arm();
    } catch (error, stackTrace) {
      debugPrint('SafeHer: threat pipeline could not arm: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 6);
      _setStatus(const ThreatPipelineStatus());
      return;
    }
    _setStatus(state.copyWith(armed: true));

    // Claimed before anything starts listening, because the thing it protects
    // is the listening itself. Without a foreground service Android freezes
    // this process when the screen goes off: the speech recogniser stops, the
    // camera policy timer stops, and the once-a-second post of the fused score
    // stops — while `armed` above goes on reporting all three as running. A
    // journey armed with no glove connected used to have no service at all,
    // because the only thing that ever started one was a connected glove.
    await _claimWatch();

    // Started together, and each isolated from the other's failure.
    //
    // These used to run in sequence, `await _startAudio` then
    // `await _startVideo`. That made the camera depend on the microphone: a
    // phone that refused speech recognition, or a missing classifier asset,
    // threw out of the first call and the weapon detector was never
    // constructed. One unavailable signal silently became two, and the fusion
    // engine cannot tell the difference between a signal that is absent
    // because the hardware is missing and one that is absent because an
    // unrelated component threw.
    //
    // `Future.wait` with `eagerError: false` starts both regardless and lets
    // each fail alone; the per-signal catch below records which one did.
    await Future.wait<void>(
      [
        _guarded('audio', () => _startAudio(aggregator)),
        _guarded('video', () => _prepareCamera(aggregator)),
      ],
      eagerError: false,
    );

    // The camera is opened by a trigger, not by arming — but the dwell has to
    // be checked by somebody, and the policy does not run itself.
    _cameraTimer?.cancel();
    _cameraTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _closeCameraIfDue(),
    );
  }

  /// Opens the camera if a trigger has just asked for it and it is not already
  /// streaming. Failure is isolated: a camera that will not open must not stop
  /// the microphone and the glove, which are the signals that opened it.
  void _openCameraIfNeeded() {
    if (_video != null || _weapons == null) return;
    unawaited(_guarded('video', _openCamera));
  }

  void _closeCameraIfDue() {
    final now = DateTime.now();
    if (!_policy.shouldClose(now: now)) return;
    _policy.close(now: now);
    unawaited(_closeCamera());
  }

  /// Runs one signal's start-up so that its failure cannot reach the others.
  ///
  /// A thrown signal is recorded as unavailable rather than swallowed. "It did
  /// not start" and "it started and heard nothing" are different facts, and
  /// only the first one should ever be shown as a warning.
  Future<void> _guarded(String signal, Future<void> Function() start) async {
    try {
      await start();
    } catch (error, stackTrace) {
      debugPrint('SafeHer: $signal signal failed to start: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 6);
      _setStatus(
        signal == 'audio'
            ? state.copyWith(audioListening: false, audioUnavailable: true)
            : state.copyWith(weaponAvailable: false),
      );
    }
  }

  /// Stops listening and hands the microphone over, keeping the pipeline armed.
  ///
  /// Distinct from [_stop]: the journey is still running and the camera is
  /// still watching. Only the audio signal pauses, and it resumes when the
  /// recording ends.
  Future<void> _releaseMicrophone() async {
    if (_audio == null) return;
    await _audioSub?.cancel();
    _audioSub = null;
    await _audio?.dispose();
    _audio = null;
    _setStatus(state.copyWith(audioListening: false, audioYieldedToEvidence: true));
  }

  Future<void> _startAudio(ThreatSignalAggregator aggregator) async {
    if (_audio != null) return;

    // Refused while evidence holds the device. Starting anyway would make the
    // two contend, and the one that loses might be the recording.
    if (!ref.read(microphoneArbiterProvider.notifier).claimForThreatListening()) {
      _setStatus(state.copyWith(audioListening: false, audioYieldedToEvidence: true));
      return;
    }

    final classifier = await ref.read(threatPhraseClassifierProvider.future);
    final monitor = AudioThreatMonitor(classifier: classifier);
    _audio = monitor;

    _audioSub = monitor.readings.listen((reading) {
      aggregator.reportAudio(reading.score, label: reading.label);
      // A frightened sentence is not an emergency on its own — the fusion
      // engine decides that — but it is reason enough to open the camera and
      // find out whether anything is in view.
      if (_policy.reportAudio(reading.score, now: DateTime.now())) {
        _openCameraIfNeeded();
      }
    });

    final started = await monitor.start();
    if (!started) {
      ref.read(microphoneArbiterProvider.notifier).releaseThreatListening();
    }
    _setStatus(state.copyWith(
      audioListening: started,
      audioUnavailable: !started,
      audioYieldedToEvidence: false,
    ));
  }

  /// Gets the detector ready while the camera stays shut.
  ///
  /// The model is loaded here, when a journey arms and nothing is waiting on
  /// it. Loading it lazily on the first frame would spend that time in the
  /// seconds immediately after a trigger — blind at the one moment the camera
  /// was opened for.
  Future<void> _prepareCamera(ThreatSignalAggregator aggregator) async {
    if (_weapons != null) return;

    // No paired glasses means no stream, and no stream means the weapon signal
    // is absent rather than zero. Absent is the honest answer: a camera that
    // does not exist has not looked and seen nothing.
    final uri = ref.read(appPreferencesProvider).glassesStreamUri;
    if (uri == null) {
      _setStatus(state.copyWith(weaponAvailable: false));
      return;
    }

    // Android scores frames on the phone; web uploads a sample of them. The
    // second is a weaker promise -- sampled rather than continuous, and the
    // frame leaves the device -- which is why `weaponOnDevice` is published
    // rather than left for the UI to assume.
    final onDevice = _canRunDetector;
    final service = WeaponDetectionService(
      detector: onDevice
          ? UltralyticsWeaponDetector()
          : RemoteWeaponDetector(
              apiClient: ref.read(apiClientProvider),
              // Deliberately shorter than the service's own 2 s interval below.
              // With both set to the same value, ordinary timing jitter makes
              // the detector reject a frame the service just released, and the
              // effective rate halves for no reason. The service is the
              // authority on pacing; this is only a backstop against a caller
              // that ignores it.
              minimumInterval: const Duration(milliseconds: 1500),
            ),
      // Uploading at the on-device rate would be a frame every 200 ms over the
      // network. The remote detector throttles itself as well; this keeps the
      // service from even trying.
      inferenceInterval:
          onDevice ? const Duration(milliseconds: 200) : const Duration(seconds: 2),
    );
    _weapons = service;

    _weaponSub = service.scores.listen((score) {
      // A score computed from an empty window is not an observation. The
      // scorer is reset whenever the camera closes, and `onStreamLost` then
      // publishes its zero — forwarding that would tell the fusion engine the
      // camera looked and saw calm, at a 0.40 weight, every time the camera
      // shut. With the camera now cycling all journey, that would quietly cap
      // the fused score and suppress the alarm the microphone and the glove
      // were raising between them.
      if (score.framesConsidered == 0) return;
      aggregator.reportWeapon(score.value, label: score.strongestLabel);
    });

    // Loads the model now, with the camera shut and nothing waiting.
    await service.prepareDetector();
    _setStatus(state.copyWith(weaponAvailable: true, weaponOnDevice: onDevice));
  }

  /// Opens the glasses' video stream, because something asked for it.
  Future<void> _openCamera() async {
    final service = _weapons;
    if (_video != null || service == null) return;

    final uri = ref.read(appPreferencesProvider).glassesStreamUri;
    if (uri == null) return;

    // The stream reaches the glasses through the same mDNS-resolving client
    // pairing uses, so `safeher-glasses.local` connects on Android too. The
    // resolver's cache is shared, so reconnects do not re-query.
    final stream = GlassesVideoStream(
      streamUri: uri,
      dio: glassesDio(resolver: ref.read(glassesResolverProvider)),
    );
    _video = stream;
    // Published so the Devices screen's live preview can watch these frames
    // rather than opening a second connection: the glasses serve one video
    // client, and a second one would evict the detector. See
    // `activeGlassesVideoStreamProvider`.
    ref.read(activeGlassesVideoStreamProvider.notifier).state = stream;

    _videoStatusSub = stream.statuses.listen((status) {
      if (status != GlassesStreamStatus.streaming) service.onStreamLost();
      _setStatus(state.copyWith(
        glassesStreaming: status == GlassesStreamStatus.streaming,
      ));
    });

    service.watch(stream.frames);
    await stream.start();
    _setStatus(state.copyWith(cameraOpen: true));
    debugPrint('SafeHer: camera opened by ${_policy.openedBy?.name}');
  }

  /// Closes the camera and withdraws the weapon signal.
  ///
  /// Both halves matter. Stopping the stream frees the glasses' single video
  /// client and stops paying for a radio nobody is reading; retracting the
  /// signal is what keeps a shut camera *absent* from the fusion payload
  /// rather than reported as calm.
  Future<void> _closeCamera() async {
    final stream = _video;
    if (stream == null) return;
    _video = null;

    await _videoStatusSub?.cancel();
    _videoStatusSub = null;
    await stream.stop();
    ref.read(activeGlassesVideoStreamProvider.notifier).state = null;

    // Frames from this opening must not vote alongside frames from the next
    // one: a knife glimpsed in each is two glimpses of different moments, not
    // one persistent threat. The zero this publishes is filtered above.
    _weapons?.onStreamLost();
    ref.read(threatSignalAggregatorProvider).retractWeapon();

    _setStatus(state.copyWith(cameraOpen: false, glassesStreaming: false));
    debugPrint('SafeHer: camera closed');
  }

  /// The detector is Android-only. On web the plugin has no implementation, and
  /// starting it would produce a service that reports calm from a model that
  /// never ran — the exact failure this codebase keeps having to remove.
  bool get _canRunDetector =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _stop() async {
    _cameraTimer?.cancel();
    _cameraTimer = null;
    // Cleared rather than left to expire: the next journey must not begin
    // inside this one's dwell or cooldown.
    _policy.reset();

    await _audioSub?.cancel();
    await _weaponSub?.cancel();
    await _videoStatusSub?.cancel();
    _audioSub = null;
    _weaponSub = null;
    _videoStatusSub = null;

    await _audio?.dispose();
    await _video?.stop();
    await _weapons?.dispose();
    _audio = null;
    _video = null;
    _weapons = null;
    // Cleared before anything else can borrow a stopped stream and render its
    // last frame as though the camera were still watching.
    ref.read(activeGlassesVideoStreamProvider.notifier).state = null;

    ref.read(threatSignalAggregatorProvider).disarm();
    ref.read(microphoneArbiterProvider.notifier).releaseThreatListening();
    await _releaseWatch();
    _setStatus(const ThreatPipelineStatus());
  }

  /// Claims the background watch, reporting failure rather than throwing.
  ///
  /// A phone that refuses the foreground service — notification permission
  /// denied, or an OEM that kills background work — still detects perfectly
  /// well while the app is on screen, so this must not take the pipeline down
  /// with it. What it must not do is leave the app *claiming* the
  /// phone-in-pocket case works: `SafetyWatch` publishes whether the service
  /// is genuinely running, and the Profile screen reads that value.
  Future<void> _claimWatch() async {
    try {
      await _watch.claim(WatchReason.journey);
    } on Object catch (error) {
      debugPrint('SafeHer: could not claim the background watch: $error');
    }
  }

  /// Releases the journey's claim. The glove's claim, if it has one, keeps the
  /// service alive — ending a journey must not stop the glove being watched.
  Future<void> _releaseWatch() async {
    try {
      await _watch.release(WatchReason.journey);
    } on Object catch (error) {
      // Disposal is a routine caller here, and a notifier that has already
      // been torn down cannot be told anything. `SafetyWatch`'s own teardown
      // stops the service in that case, so nothing is left running.
      debugPrint('SafeHer: could not release the background watch: $error');
    }
  }

  /// Single place every status change goes through, so the mirror the UI reads
  /// can never drift from what is actually running.
  void _setStatus(ThreatPipelineStatus next) {
    state = next;
    ref.read(journeyDetectionStatusProvider.notifier).publish(next);
  }
}

/// What is actually running, as opposed to what was asked for.
@immutable
class ThreatPipelineStatus {
  const ThreatPipelineStatus({
    this.armed = false,
    this.audioListening = false,
    this.audioUnavailable = false,
    this.cameraOpen = false,
    this.glassesStreaming = false,
    this.weaponAvailable = false,
    this.weaponOnDevice = false,
    this.audioYieldedToEvidence = false,
  });

  final bool armed;

  /// The microphone is open and scoring.
  final bool audioListening;

  /// The platform refused the microphone or has no recogniser. Distinct from
  /// simply not listening, because the UI must not offer to turn on something
  /// that cannot be turned on.
  final bool audioUnavailable;

  /// The camera has been asked to stream, because the microphone or the glove
  /// suggested something is happening.
  ///
  /// Distinct from [glassesStreaming], and the difference is the honest part:
  /// this says the app opened the camera, that one says video is actually
  /// arriving. A pair of glasses that has gone flat leaves this true and that
  /// false, which is precisely what the user needs to be told.
  final bool cameraOpen;

  /// Video is genuinely arriving — the platform's answer, not this app's
  /// intention. A dead stream must never read as "watching and seeing nothing".
  final bool glassesStreaming;

  /// Glasses are paired and something is scoring their frames.
  final bool weaponAvailable;

  /// Whether that scoring happens on the phone.
  ///
  /// False means the web fallback: frames are uploaded and sampled rather than
  /// scored continuously on the device. Those are different promises and the
  /// UI must not present them as one.
  final bool weaponOnDevice;

  /// Listening paused because evidence recording holds the microphone.
  ///
  /// Not the same as unavailable: nothing is broken and it resumes on its own.
  /// The UI must not warn about it.
  final bool audioYieldedToEvidence;

  ThreatPipelineStatus copyWith({
    bool? armed,
    bool? audioListening,
    bool? audioUnavailable,
    bool? cameraOpen,
    bool? glassesStreaming,
    bool? weaponAvailable,
    bool? weaponOnDevice,
    bool? audioYieldedToEvidence,
  }) =>
      ThreatPipelineStatus(
        armed: armed ?? this.armed,
        audioListening: audioListening ?? this.audioListening,
        audioUnavailable: audioUnavailable ?? this.audioUnavailable,
        cameraOpen: cameraOpen ?? this.cameraOpen,
        glassesStreaming: glassesStreaming ?? this.glassesStreaming,
        weaponAvailable: weaponAvailable ?? this.weaponAvailable,
        weaponOnDevice: weaponOnDevice ?? this.weaponOnDevice,
        audioYieldedToEvidence:
            audioYieldedToEvidence ?? this.audioYieldedToEvidence,
      );
}
