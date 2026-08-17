/// Whether automatic threat detection is actually running — SRS FR-EMG-02.
///
/// **Why this exists.** SafeHer's Profile screen has a "threat threshold"
/// slider. For a long time it wrote to local storage and was read by nothing:
/// a user could set it to 60% and reasonably believe SafeHer would raise the
/// alarm for her. The threshold now reaches the server and the server acts on
/// it, but the decision still needs a *score* — and those come from three
/// models (XGBoost over the glove's motion, CNN+LSTM over the glasses'
/// microphone, YOLOv8 over its camera) that are not trained yet.
///
/// So the honest state today is: the machinery is complete and nothing feeds
/// it. A control that silently governs nothing is worse than no control at
/// all on a safety app, because it is indistinguishable from protection.
///
/// The obvious shortcut — post the phone's raw accelerometer magnitude as a
/// "motion score" — is deliberately not taken. It would be an invented number
/// wearing a model's name, it would dispatch to every emergency contact on a
/// dropped phone or a run for a bus, and each false alarm spends the
/// credibility the real alert depends on. The phone already has an honest
/// trigger for its own hardware: the deliberate shake gesture, which opens
/// the countdown rather than dispatching directly.
library;

import 'package:flutter/foundation.dart';

/// What the backend reports about the detection pipeline.
@immutable
class DetectionStatus {
  const DetectionStatus({
    required this.pipelineLive,
    required this.anyModelReady,
    required this.scoresAreCallerSupplied,
    this.models = const [],
  });

  /// Every model is trained and serving.
  final bool pipelineLive;

  /// At least one model is serving, so *some* modality is scored.
  final bool anyModelReady;

  /// No model is trained, so any score the backend holds came from a caller
  /// rather than from SafeHer's own inference. Reported plainly because the
  /// difference decides whether a threshold means anything.
  final bool scoresAreCallerSupplied;

  final List<DetectionModel> models;

  /// Whether an automatic alarm can currently be raised without the user.
  bool get autoSosActive => anyModelReady;

  /// One line the user can act on, in her words rather than the system's.
  String get headline => autoSosActive
      ? 'Automatic detection is on'
      : 'Automatic detection is not active yet';

  String get detail => autoSosActive
      ? 'SafeHer raises the alarm on its own when the threat score passes your '
            'threshold.'
      : 'Your wearables are not sending readings, so SafeHer cannot detect a '
            'threat by itself. SOS, the shake gesture and your emergency '
            'contacts all work as normal.';

  factory DetectionStatus.fromJson(Map<String, dynamic> json) => DetectionStatus(
        pipelineLive: json['pipeline_live'] as bool? ?? false,
        anyModelReady: json['any_ready'] as bool? ?? false,
        scoresAreCallerSupplied: json['scores_are_caller_supplied'] as bool? ?? true,
        models: (json['models'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DetectionModel.fromJson)
            .toList(growable: false),
      );

  /// The state to assume when the backend cannot be reached.
  ///
  /// Pessimistic on purpose: claiming detection is running when we do not
  /// know is the one error that could stop someone acting for herself.
  static const unknown = DetectionStatus(
    pipelineLive: false,
    anyModelReady: false,
    scoresAreCallerSupplied: true,
  );
}

@immutable
class DetectionModel {
  const DetectionModel({
    required this.modality,
    required this.algorithm,
    required this.sourceDevice,
    required this.status,
  });

  final String modality;
  final String algorithm;
  final String sourceDevice;
  final String status;

  bool get isReady => status == 'ready';

  /// "Motion from the glove", rather than "motion | XGBoost | glove".
  String get label => '${modality[0].toUpperCase()}${modality.substring(1)} '
      'from the $sourceDevice';

  factory DetectionModel.fromJson(Map<String, dynamic> json) => DetectionModel(
        modality: json['modality'] as String? ?? 'unknown',
        algorithm: json['algorithm'] as String? ?? 'unknown',
        sourceDevice: json['source_device'] as String? ?? 'unknown',
        status: json['status'] as String? ?? 'untrained',
      );
}
