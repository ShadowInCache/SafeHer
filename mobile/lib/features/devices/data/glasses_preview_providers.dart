import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/app_preferences.dart';
import 'glasses_dio.dart';
import 'glasses_providers.dart';
import 'mjpeg_client.dart';

/// The video stream weapon detection is currently pulling, or null when no
/// Safe Journey is armed.
///
/// Published by `ThreatPipeline` at the two moments that matter — the stream
/// being created and being torn down — so anything else that wants to look at
/// the camera can join that stream instead of opening a second one.
///
/// **The glasses serve exactly one video client.** `SafeHer_Glasses_Stream.ino`
/// keeps a single `WiFiClient videoClient` and calls `videoClient.stop()` on
/// the old one whenever a new request for `/stream` arrives. So a preview that
/// connected on its own while a journey was running would evict the detector,
/// the detector would reconnect and evict the preview, and the two would thrash
/// — with weapon detection losing frames the whole time. That is why this
/// exists rather than the preview simply making its own connection.
final activeGlassesVideoStreamProvider =
    StateProvider<GlassesVideoStream?>((ref) => null);

/// Where the preview's frames come from, and whether it owns that stream.
class GlassesPreviewSource {
  const GlassesPreviewSource({required this.stream, required this.isShared});

  final GlassesVideoStream stream;

  /// True when these are the detector's frames, borrowed rather than opened.
  /// The UI says so, because "what the camera sees" and "what weapon detection
  /// is scoring" are the same picture only in this case.
  final bool isShared;
}

/// Resolves the preview's source: the detector's stream if one is running,
/// otherwise a new connection that lives only as long as something watches.
///
/// `autoDispose`, so closing the sheet releases the camera slot. Nothing here
/// records: frames are decoded to the screen and dropped.
final glassesPreviewSourceProvider =
    Provider.autoDispose<GlassesPreviewSource?>((ref) {
  final active = ref.watch(activeGlassesVideoStreamProvider);
  if (active != null) {
    // Borrowed. Deliberately not stopped on dispose — it belongs to the
    // pipeline, and stopping it here would disable weapon detection.
    return GlassesPreviewSource(stream: active, isShared: true);
  }

  final uri = ref.watch(appPreferencesProvider).glassesStreamUri;
  if (uri == null) return null;

  final stream = GlassesVideoStream(
    streamUri: uri,
    dio: glassesDio(resolver: ref.read(glassesResolverProvider)),
  );
  // `stop()` rather than `dispose()`: dispose is marked visibleForTesting, and
  // stop already closes the socket and ends the retry loop, which is what frees
  // the camera's single client slot.
  ref.onDispose(() => unawaited(stream.stop()));
  unawaited(stream.start());
  return GlassesPreviewSource(stream: stream, isShared: false);
});

/// JPEG frames for the preview. Empty when no camera is paired.
final glassesPreviewFramesProvider =
    StreamProvider.autoDispose<Uint8List>((ref) {
  final source = ref.watch(glassesPreviewSourceProvider);
  return source?.stream.frames ?? const Stream<Uint8List>.empty();
});

/// Whether video is genuinely arriving, as the platform reports it rather than
/// as the app hopes. A dead stream must read as "not connected", never as a
/// frozen last frame presented as live.
final glassesPreviewStatusProvider =
    StreamProvider.autoDispose<GlassesStreamStatus>((ref) {
  final source = ref.watch(glassesPreviewSourceProvider);
  if (source == null) return const Stream<GlassesStreamStatus>.empty();
  return source.stream.statuses;
});
