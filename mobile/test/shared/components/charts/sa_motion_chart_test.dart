import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/charts/sa_motion_chart.dart';

import '../../../test_utils/widget_test_helpers.dart';

List<MotionSample> _samples() => List.generate(30, (i) {
  return MotionSample(x: (i % 5).toDouble(), y: (i % 3).toDouble(), z: (i % 7).toDouble());
});

void main() {
  group('SaMotionChart', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaMotionChart(samples: _samples()), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaMotionChart(samples: _samples())));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles fewer than 2 samples without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaMotionChart(samples: [])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping near an event pin invokes onPinTap', (tester) async {
      MotionEventPin? tapped;
      final pin = const MotionEventPin(sampleIndex: 0, label: 'Sudden jolt', timestamp: '10:02:03');
      await tester.pumpWidget(
        wrapWithTheme(
          SaMotionChart(samples: _samples(), events: [pin], onPinTap: (p) => tapped = p),
          surfaceSize: const Size(300, 150),
        ),
      );
      await tester.tapAt(tester.getTopLeft(find.byType(SaMotionChart)) + const Offset(2, 10));
      await tester.pump();
      expect(tapped?.label, 'Sudden jolt');
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(
          height: 120,
          child: SaMotionChart(
            samples: _samples(),
            events: const [MotionEventPin(sampleIndex: 15, label: 'Impact', timestamp: '10:02:03')],
          ),
        ),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 160)),
        surfaceSize: const Size(320, 160),
      );
      await screenMatchesGolden(tester, 'sa_motion_chart_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(
          height: 120,
          child: SaMotionChart(
            samples: _samples(),
            events: const [MotionEventPin(sampleIndex: 15, label: 'Impact', timestamp: '10:02:03')],
          ),
        ),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 160)),
        surfaceSize: const Size(320, 160),
      );
      await screenMatchesGolden(tester, 'sa_motion_chart_dark');
    });
  });
}
