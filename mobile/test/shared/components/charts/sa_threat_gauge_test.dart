import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/shared/components/charts/sa_threat_gauge.dart';

import '../../../test_utils/widget_test_helpers.dart';

/// The gauge shows its value on the first frame; only the danger glow is
/// deferred by one. This settles both.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  group('SaThreatGauge', () {
    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.3), brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.3)));
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    });

    testWidgets('animates smoothly when score changes', (tester) async {
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.2)));
      await _settle(tester);
      // Shown immediately, not swept up from zero.
      expect(find.text('20'), findsOneWidget);

      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.85)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      // A change does animate: mid-flight the reading is between the two.
      final midpoint = int.parse(
        tester.widget<Text>(find.byType(Text).first).data!,
      );
      expect(midpoint, greaterThan(20));

      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('85'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaThreatGauge(score: 0.35),
        wrapper: (child) => wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      await _settle(tester);
      // Guards the golden itself: a capture taken before the entrance
      // animation ran would show a 0 gauge and quietly become the reference.
      expect(find.text('35'), findsOneWidget);
      await screenMatchesGolden(tester, 'sa_threat_gauge_light');
    });

    testWidgets('the score stays legible at DANGER', (tester) async {
      // The bug this redesign fixes: the old centre-pivoted needle swept
      // through the middle of the dial, which is where the score and state
      // are drawn — at DANGER it crossed the word "DANGER" itself. Both
      // must be present and findable at the top of the range.
      await tester.pumpWidget(wrapWithTheme(const SaThreatGauge(score: 0.95)));
      await _settle(tester);

      expect(find.text('95'), findsOneWidget);
      expect(find.text('DANGER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the readout stays inside the dial at 200% font scale', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          // AppTheme, not a bare MaterialApp: the gauge reads the SafeHer
          // colour extension, which only exists on the app's own themes.
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Scaffold(
              body: Center(child: SaThreatGauge(score: 0.95, size: 140)),
            ),
          ),
        ),
      );
      await _settle(tester);

      // FittedBox shrinks the text rather than letting it grow into the arc.
      expect(tester.takeException(), isNull);
      final gauge = tester.getRect(find.byType(SaThreatGauge));
      final score = tester.getRect(find.text('95'));
      expect(gauge.contains(score.topLeft), isTrue);
      expect(gauge.contains(score.bottomRight), isTrue);
    });

    testGoldens('golden - light at DANGER', (tester) async {
      // Light mode at the top of the range: the track is near-white there,
      // so this is where a low-contrast arc would show up.
      await tester.pumpWidgetBuilder(
        const SaThreatGauge(score: 0.9),
        wrapper: (child) =>
            wrapWithTheme(child, brightness: Brightness.light, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      await _settle(tester);
      await screenMatchesGolden(
        tester,
        'sa_threat_gauge_light_danger',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(
        const SaThreatGauge(score: 0.82),
        wrapper: (child) => wrapWithTheme(child, surfaceSize: const Size(220, 220)),
        surfaceSize: const Size(220, 220),
      );
      await _settle(tester);
      // Not the default pumpAndSettle: the DANGER glow breathes on a repeat
      // (SRS "glowPulse"), so nothing ever settles.
      await screenMatchesGolden(
        tester,
        'sa_threat_gauge_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
