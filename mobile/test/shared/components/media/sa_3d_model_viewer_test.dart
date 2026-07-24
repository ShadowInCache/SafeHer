import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/shared/components/media/sa_3d_model_viewer.dart';

import '../../../test_utils/fake_webview_platform.dart';
import '../../../test_utils/widget_test_helpers.dart';

void main() {
  setUpAll(FakeWebViewPlatform.install);

  group('Sa3DModelViewer', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const Sa3DModelViewer(src: SaSampleModels.astronaut, alt: 'Rotating shield model'),
          brightness: Brightness.light,
        ),
      );
      expect(tester.takeException(), isNull);
      // The proxy HttpServer bind is real (non-fake-clock) async I/O; give
      // it a chance to resolve and trigger setState before asserting.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Rotating shield model'), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const Sa3DModelViewer(src: SaSampleModels.astronaut, alt: 'Rotating shield model')),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Rotating shield model'), findsOneWidget);
    });
  });
}
