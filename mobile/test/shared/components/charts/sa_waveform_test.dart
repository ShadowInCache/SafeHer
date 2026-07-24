import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/shared/components/charts/sa_waveform.dart';

import '../../../test_utils/widget_test_helpers.dart';

List<double> _sampleWave() => List.generate(64, (i) => (i % 8) / 8);

void main() {
  group('SaWaveform', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaWaveform(amplitudes: _sampleWave()), brightness: Brightness.light));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(SaWaveform(amplitudes: _sampleWave())));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles fewer samples than barCount without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaWaveform(amplitudes: [0.2, 0.5, 0.8])));
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles empty amplitudes without exception', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaWaveform(amplitudes: [])));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(width: 300, height: 64, child: SaWaveform(amplitudes: _sampleWave())),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_waveform_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        SizedBox(width: 300, height: 64, child: SaWaveform(amplitudes: _sampleWave())),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(320, 100)),
        surfaceSize: const Size(320, 100),
      );
      await screenMatchesGolden(tester, 'sa_waveform_dark');
    });
  });
}
