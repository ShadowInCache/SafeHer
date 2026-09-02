import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/audio/audio_threat_monitor.dart';
import '../../../core/audio/threat_phrase_classifier.dart';
import '../../../core/local/app_preferences.dart';
import '../../../core/network/network_providers.dart';
import '../../devices/data/glove_link_providers.dart';
import '../../devices/data/mjpeg_client.dart';
import '../../devices/data/ultralytics_weapon_detector.dart';
import '../../devices/data/weapon_detection_service.dart';
import '../../../shared/models/threat_level.dart';
import '../../devices/domain/glove_protocol.dart';
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

  @override
  ThreatPipelineStatus build() {
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
      ref.read(threatSignalAggregatorProvider).reportGlove(
            gloveScore(classification),
            label: classification.label,
          );
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
    final aggregator = ref.read(threatSignalAggregatorProvider)..arm();
    await _startAudio(aggregator);
    await _startVideo(aggregator);
    _publish();
  }

  Future<void> _startAudio(ThreatSignalAggregator aggregator) async {
    if (_audio != null) return;

    final classifier = await ref.read(threatPhraseClassifierProvider.future);
    final monitor = AudioThreatMonitor(classifier: classifier);
    _audio = monitor;

    _audioSub = monitor.readings.listen((reading) {
      aggregator.reportAudio(reading.score, label: reading.label);
    });

    final started = await monitor.start();
    _setStatus(state.copyWith(
      audioListening: started,
      audioUnavailable: !started,
    ));
  }

  Future<void> _startVideo(ThreatSignalAggregator aggregator) async {
    if (_video != null) return;

    // No paired glasses means no stream, and no stream means the weapon signal
    // is absent rather than zero. Absent is the honest answer: a camera that
    // does not exist has not looked and seen nothing.
    final uri = ref.read(appPreferencesProvider).glassesStreamUri;
    if (uri == null || !_canRunDetector) {
      _setStatus(state.copyWith(weaponAvailable: false));
      return;
    }

    final service = WeaponDetectionService(
      detector: UltralyticsWeaponDetector(),
    );
    final stream = GlassesVideoStream(streamUri: uri);
    _weapons = service;
    _video = stream;

    _weaponSub = service.scores.listen((score) {
      aggregator.reportWeapon(score.value, label: score.strongestLabel);
    });

    _videoStatusSub = stream.statuses.listen((status) {
      if (status != GlassesStreamStatus.streaming) service.onStreamLost();
      _setStatus(state.copyWith(
        glassesStreaming: status == GlassesStreamStatus.streaming,
      ));
    });

    service.watch(stream.frames);
    await stream.start();
    _setStatus(state.copyWith(weaponAvailable: true));
  }

  /// The detector is Android-only. On web the plugin has no implementation, and
  /// starting it would produce a service that reports calm from a model that
  /// never ran — the exact failure this codebase keeps having to remove.
  bool get _canRunDetector =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _stop() async {
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

    ref.read(threatSignalAggregatorProvider).disarm();
    _setStatus(const ThreatPipelineStatus());
  }

  void _publish() => _setStatus(state.copyWith(armed: true));

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
    this.glassesStreaming = false,
    this.weaponAvailable = false,
  });

  final bool armed;

  /// The microphone is open and scoring.
  final bool audioListening;

  /// The platform refused the microphone or has no recogniser. Distinct from
  /// simply not listening, because the UI must not offer to turn on something
  /// that cannot be turned on.
  final bool audioUnavailable;

  /// Video is genuinely arriving — the platform's answer, not this app's
  /// intention. A dead stream must never read as "watching and seeing nothing".
  final bool glassesStreaming;

  /// Glasses are paired and this platform can run the detector.
  final bool weaponAvailable;

  ThreatPipelineStatus copyWith({
    bool? armed,
    bool? audioListening,
    bool? audioUnavailable,
    bool? glassesStreaming,
    bool? weaponAvailable,
  }) =>
      ThreatPipelineStatus(
        armed: armed ?? this.armed,
        audioListening: audioListening ?? this.audioListening,
        audioUnavailable: audioUnavailable ?? this.audioUnavailable,
        glassesStreaming: glassesStreaming ?? this.glassesStreaming,
        weaponAvailable: weaponAvailable ?? this.weaponAvailable,
      );
}
