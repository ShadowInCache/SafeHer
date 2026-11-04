import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/glasses_preview_providers.dart';
import 'package:safeher_app/features/devices/data/mjpeg_client.dart';
import 'package:safeher_app/features/devices/data/weapon_detection_service.dart';
import 'package:safeher_app/features/devices/data/weapon_overlay_providers.dart';
import 'package:safeher_app/features/devices/domain/weapon_overlay.dart';
import 'package:safeher_app/features/devices/domain/weapon_scorer.dart';
import 'package:safeher_app/features/devices/presentation/widgets/glasses_live_preview.dart';
import 'package:safeher_app/features/devices/presentation/widgets/weapon_detection_overlay.dart';

/// The overlay as the user meets it: boxes over the live picture, and a line
/// underneath saying what the detector is doing.
///
/// That status line is not decoration. A preview showing no boxes is ambiguous
/// — the model may have looked and seen nothing, or may not be running at all —
/// and this project has shipped a control that governed nothing five separate
/// times. The tests below treat "says it is not running" as a feature.
final _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _StubDetector implements WeaponDetector {
  @override
  Future<void> prepare() async {}
  @override
  Future<List<WeaponDetection>> detect(Uint8List jpegFrame) async => const [];
  @override
  Future<void> dispose() async {}
  @override
  Size? get lastFrameSize => const Size(640, 480);
}

GlassesPreviewSource _source() => GlassesPreviewSource(
      stream:
          GlassesVideoStream(streamUri: Uri.parse('http://camera.local/stream')),
      isShared: false,
    );

Widget _harness({
  required bool detectorRunning,
  bool framesArriving = true,
  WeaponOverlayState? overlay,
}) {
  return ProviderScope(
    overrides: [
      glassesPreviewSourceProvider.overrideWith((ref) => _source()),
      glassesPreviewFramesProvider
          .overrideWith((ref) => Stream<Uint8List>.value(_onePixelPng)),
      glassesPreviewStatusProvider.overrideWith(
        (ref) => Stream<GlassesStreamStatus>.value(
          GlassesStreamStatus.streaming,
        ),
      ),
      weaponOverlayDetectorProvider.overrideWith((ref) {
        if (!detectorRunning) return null;
        final service = WeaponDetectionService(detector: _StubDetector());
        // A loaded detector that has been sent nothing is the ordinary case
        // during a Safe Journey, because the camera is opened by a trigger
        // rather than by arming. It must not read as "watching".
        if (framesArriving) {
          service.watch(Stream<Uint8List>.value(_onePixelPng));
        }
        return service;
      }),
      weaponOverlayStateProvider.overrideWith(
        (ref) => overlay == null
            ? const Stream<WeaponOverlayState>.empty()
            : Stream<WeaponOverlayState>.value(overlay),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: GlassesLivePreview())),
    ),
  );
}

Future<void> _show(WidgetTester tester) async {
  await tester.tap(find.text('Show'));
  await tester.pump();
  await tester.pump();
}

void main() {
  WeaponOverlayState stateWith(
    List<WeaponDetection> detections, {
    required DateTime at,
  }) =>
      const WeaponOverlayState()
          .withFrame(detections, at: at, frameSize: const Size(640, 480));

  WeaponDetection knife(DateTime at, {double confidence = 0.84}) =>
      WeaponDetection(
        label: 'knife',
        confidence: confidence,
        at: at,
        box: const WeaponBox(left: 0.2, top: 0.2, right: 0.6, bottom: 0.7),
      );

  testWidgets('says so when the detector is not running', (tester) async {
    await tester.pumpWidget(_harness(detectorRunning: false));
    await _show(tester);

    expect(find.textContaining('not running'), findsOneWidget);
    expect(find.byType(WeaponDetectionOverlay), findsNothing);
  });

  testWidgets('says it is watching when nothing has been seen', (tester) async {
    await tester.pumpWidget(_harness(
      detectorRunning: true,
      overlay: stateWith(const [], at: DateTime.now()),
    ));
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.textContaining('no weapon detected'), findsOneWidget);
    expect(find.byType(WeaponDetectionOverlay), findsNothing);
  });

  testWidgets('does not claim to be watching before a frame has arrived',
      (tester) async {
    // The defect this pins cost a whole hardware session: during a journey the
    // camera is opened by a trigger, so a loaded detector routinely receives
    // nothing — and the line said "Watching — no weapon detected", which is
    // the app asserting it looked at the street and found it calm.
    await tester.pumpWidget(_harness(
      detectorRunning: true,
      framesArriving: false,
      overlay: stateWith(const [], at: DateTime.now()),
    ));
    await _show(tester);
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.textContaining('No video reaching the detector'), findsOneWidget);
    expect(find.textContaining('no weapon detected'), findsNothing,
        reason: 'nothing was examined, so nothing can be reported as absent');
  });

  testWidgets('draws the box and names the weapon with its confidence',
      (tester) async {
    await tester.pumpWidget(_harness(
      detectorRunning: true,
      overlay: stateWith([knife(DateTime.now())], at: DateTime.now()),
    ));
    await _show(tester);

    expect(find.byType(WeaponDetectionOverlay), findsOneWidget);
    expect(find.text('Weapon detected: knife 84%'), findsOneWidget);
  });

  testWidgets('counts multiple weapons in the status line', (tester) async {
    final at = DateTime.now();
    await tester.pumpWidget(_harness(
      detectorRunning: true,
      overlay: stateWith([
        knife(at, confidence: 0.84),
        WeaponDetection(
          label: 'pistol',
          confidence: 0.91,
          at: at,
          box: const WeaponBox(left: 0.1, top: 0.1, right: 0.3, bottom: 0.4),
        ),
      ], at: at),
    ));
    await _show(tester);

    expect(find.textContaining('2 weapons detected'), findsOneWidget);
    expect(find.textContaining('pistol 91%'), findsOneWidget,
        reason: 'the strongest is named, not the first');
  });

  testWidgets('an aged-out detection leaves no box behind', (tester) async {
    // The video is still playing; the inference simply stopped arriving. A
    // rectangle left over a live stream is the worst thing this can show,
    // because it reports a working detector where there is none.
    final stale = DateTime.now().subtract(const Duration(seconds: 5));
    await tester.pumpWidget(_harness(
      detectorRunning: true,
      overlay: stateWith([knife(stale)], at: stale),
    ));
    await _show(tester);

    expect(find.byType(WeaponDetectionOverlay), findsNothing);
    expect(find.textContaining('no weapon detected'), findsOneWidget);
  });

  testWidgets('the video is still shown when the overlay has nothing to say',
      (tester) async {
    await tester.pumpWidget(_harness(detectorRunning: false));
    await _show(tester);

    expect(find.byType(Image), findsOneWidget,
        reason: 'a failed or absent detector must never hide the picture');
  });
}
