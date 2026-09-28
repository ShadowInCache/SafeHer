import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/devices/data/glasses_preview_providers.dart';
import 'package:safeher_app/features/devices/data/mjpeg_client.dart';
import 'package:safeher_app/features/devices/presentation/widgets/glasses_live_preview.dart';

/// A real 1x1 PNG, so `Image.memory` actually decodes rather than reporting an
/// exception the test would then have to ignore.
final _onePixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

GlassesPreviewSource _source({bool isShared = false}) => GlassesPreviewSource(
      stream: GlassesVideoStream(streamUri: Uri.parse('http://camera.local/stream')),
      isShared: isShared,
    );

Widget _harness({
  GlassesPreviewSource? source,
  Stream<Uint8List>? frames,
  Stream<GlassesStreamStatus>? statuses,
}) {
  return ProviderScope(
    overrides: [
      glassesPreviewSourceProvider.overrideWith((ref) => source),
      glassesPreviewFramesProvider
          .overrideWith((ref) => frames ?? const Stream<Uint8List>.empty()),
      glassesPreviewStatusProvider.overrideWith(
        (ref) => statuses ?? const Stream<GlassesStreamStatus>.empty(),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: GlassesLivePreview())),
    ),
  );
}

void main() {
  testWidgets('does not touch the camera until asked', (tester) async {
    // Opening the sheet must not start a stream: the camera serves one client,
    // and a picture of someone's surroundings should appear because she asked.
    await tester.pumpWidget(_harness(source: _source()));
    await tester.pump();

    expect(find.text('Live view'), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Connecting'), findsNothing);
  });

  testWidgets('shows a frame once streaming', (tester) async {
    await tester.pumpWidget(
      _harness(
        source: _source(),
        frames: Stream<Uint8List>.value(_onePixelPng),
        statuses: Stream<GlassesStreamStatus>.value(GlassesStreamStatus.streaming),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
  });

  testWidgets('a lost camera never leaves the last frame on screen', (tester) async {
    // A frozen still presented as live would tell a woman she is being watched
    // over when nothing is arriving.
    await tester.pumpWidget(
      _harness(
        source: _source(),
        frames: Stream<Uint8List>.value(_onePixelPng),
        statuses: Stream<GlassesStreamStatus>.fromIterable(
          const [GlassesStreamStatus.streaming, GlassesStreamStatus.disconnected],
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('Lost the camera'), findsOneWidget);
  });

  testWidgets('says so when the picture is the detector\'s own', (tester) async {
    await tester.pumpWidget(
      _harness(
        source: _source(isShared: true),
        frames: Stream<Uint8List>.value(_onePixelPng),
        statuses: Stream<GlassesStreamStatus>.value(GlassesStreamStatus.streaming),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('weapon detection is scoring'), findsOneWidget);
  });

  testWidgets('explains an unpaired camera rather than spinning', (tester) async {
    await tester.pumpWidget(_harness(source: null));

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('No camera paired yet.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('hiding it releases the camera again', (tester) async {
    await tester.pumpWidget(
      _harness(
        source: _source(),
        frames: Stream<Uint8List>.value(_onePixelPng),
        statuses: Stream<GlassesStreamStatus>.value(GlassesStreamStatus.streaming),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Hide'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Show'), findsOneWidget);
  });
}
