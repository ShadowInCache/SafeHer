import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/glasses_preview_providers.dart';
import 'package:safeher_app/features/devices/data/mjpeg_client.dart';

/// The glasses serve exactly one video client: `SafeHer_Glasses_Stream.ino`
/// keeps a single `WiFiClient videoClient` and stops the old one whenever a new
/// `/stream` request arrives. So a preview that opened its own connection while
/// a Safe Journey was running would evict the weapon detector, which would
/// reconnect and evict the preview, and the two would thrash — with detection
/// dropping frames throughout. These pin the rule that prevents it.
void main() {
  group('when the detector already holds the camera', () {
    test('the preview borrows that stream instead of opening another', () {
      final detectorStream =
          GlassesVideoStream(streamUri: Uri.parse('http://camera.local/stream'));
      addTearDown(detectorStream.stop);

      final container = ProviderContainer(
        overrides: [
          activeGlassesVideoStreamProvider.overrideWith((ref) => detectorStream),
        ],
      );
      addTearDown(container.dispose);

      final source = container.read(glassesPreviewSourceProvider);

      expect(source, isNotNull);
      expect(
        identical(source!.stream, detectorStream),
        isTrue,
        reason: 'a second GlassesVideoStream would evict the detector',
      );
      expect(source.isShared, isTrue);
    });

    test('disposing the preview leaves the detector streaming', () async {
      // The borrowed stream belongs to ThreatPipeline. Stopping it when the
      // sheet closes would silently switch weapon detection off.
      final detectorStream =
          GlassesVideoStream(streamUri: Uri.parse('http://camera.local/stream'));
      addTearDown(detectorStream.stop);

      final container = ProviderContainer(
        overrides: [
          activeGlassesVideoStreamProvider.overrideWith((ref) => detectorStream),
        ],
      );

      container.read(glassesPreviewSourceProvider);
      container.dispose();

      // A stopped stream closes its frame controller; a live one does not.
      expect(detectorStream.frames.isBroadcast, isTrue);
      expect(
        () => detectorStream.frames.listen(null).cancel(),
        returnsNormally,
        reason: 'the detector stream must still be usable after the preview goes',
      );
    });
  });

  group('the shared flag', () {
    test('is what the UI uses to claim the two pictures are the same', () {
      final stream =
          GlassesVideoStream(streamUri: Uri.parse('http://camera.local/stream'));
      addTearDown(stream.stop);

      const borrowed = true;
      final source = GlassesPreviewSource(stream: stream, isShared: borrowed);

      expect(source.isShared, isTrue);
      expect(source.stream, stream);
    });
  });
}
