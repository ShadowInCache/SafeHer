
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../domain/weapon_scorer.dart';
import 'weapon_detection_service.dart';

/// Scores frames by uploading them, for the platform that cannot do it itself.
///
/// **This is the web fallback and nothing else.** On Android
/// `UltralyticsWeaponDetector` runs the model on the phone against a continuous
/// stream and no frame ever leaves the device. Web has no on-device runtime, so
/// it posts a frame to `/alerts/weapon-frame` instead.
///
/// The two are not the same promise, and the UI is required to say which is
/// running:
///
///     Android   continuous, ~5 fps, on-device      nothing leaves the phone
///     web       sampled, on demand, server-side    the frame is uploaded
///
/// ## Why the sampling rate is so much lower
///
/// Every frame is a network round trip and a CPU inference on a shared server.
/// [minimumInterval] is deliberately far above the Android path's 200 ms: at a
/// frame every two seconds the server rate limit allows a ten-minute journey,
/// and the scorer still sees enough frames to require persistence rather than
/// trusting one.
///
/// ## An unavailable model is not a calm one
///
/// When the server reports `available: false` — nobody deployed the model, or
/// the inference extras are not installed — this throws rather than returning
/// an empty list. `WeaponDetectionService` records nothing for a failed
/// inference, so the modality stays *absent*. Returning `[]` would record a
/// frame that was examined and held no weapon, which is a claim nobody made.
class RemoteWeaponDetector implements WeaponDetector {
  RemoteWeaponDetector({
    required ApiClient apiClient,
    this.minimumInterval = const Duration(seconds: 2),
  }) : _apiClient = apiClient;

  final ApiClient _apiClient;
  final Duration minimumInterval;

  DateTime? _lastUpload;
  bool _serverHasNoModel = false;

  /// True once the server has said it cannot score frames.
  ///
  /// Sticky on purpose: a deployment without the model will not grow one
  /// mid-journey, and re-asking every two seconds spends the user's data to be
  /// told the same thing.
  bool get unavailable => _serverHasNoModel;

  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async {
    if (_serverHasNoModel) {
      throw const WeaponDetectorUnavailable('server has no weapon model');
    }

    final now = DateTime.now();
    final last = _lastUpload;
    if (last != null && now.difference(last) < minimumInterval) {
      // Not an error and not a detection — the caller records nothing, which
      // leaves the previous frames' window untouched.
      throw const WeaponDetectorThrottled();
    }
    _lastUpload = now;

    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        jpegFrame,
        filename: 'frame.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/alerts/weapon-frame',
      data: form,
    );

    final body = response.data ?? const {};
    if (body['available'] != true) {
      _serverHasNoModel = true;
      throw const WeaponDetectorUnavailable('server reported no model');
    }

    final confidence = (body['weapon_confidence'] as num?)?.toDouble();
    final label = body['weapon_label'] as String?;
    if (confidence == null || label == null) return const [];

    return [
      WeaponDetection(label: label, confidence: confidence, at: DateTime.now()),
    ];
  }

  @override
  Future<void> dispose() async {}
}

/// The server cannot score frames at all.
@immutable
class WeaponDetectorUnavailable implements Exception {
  const WeaponDetectorUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'WeaponDetectorUnavailable($reason)';
}

/// This frame arrived too soon after the last upload.
@immutable
class WeaponDetectorThrottled implements Exception {
  const WeaponDetectorThrottled();

  @override
  String toString() => 'WeaponDetectorThrottled()';
}
