import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/dashboard/domain/models/dashboard_analytics.dart';
import 'package:safeher_app/shared/components/buttons/sa_button.dart';
import 'package:safeher_app/shared/components/cards/sa_alert_card.dart';
import 'package:safeher_app/shared/components/cards/sa_card.dart';
import 'package:safeher_app/shared/components/cards/sa_contact_card.dart';
import 'package:safeher_app/shared/components/cards/sa_stat_card.dart';
import 'package:safeher_app/shared/components/charts/sa_heat_grid.dart';
import 'package:safeher_app/shared/components/feedback/sa_battery_bar.dart';
import 'package:safeher_app/shared/components/feedback/sa_empty_state.dart';
import 'package:safeher_app/shared/components/feedback/sa_threat_chip.dart';
import 'package:safeher_app/shared/components/inputs/sa_text_field.dart';
import 'package:safeher_app/shared/components/navigation/sa_bottom_nav_bar.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

/// SRS §5.4 and the ACCESSIBILITY acceptance criteria: "Font scale 200%: no
/// overflow, no clipped text".
///
/// Flutter surfaces a `RenderFlex` overflow as a framework exception during
/// a test, so `tester.takeException()` is a genuine assertion here rather
/// than a formality — a component whose label runs out of its pill at 200%
/// fails this file.
///
/// Components are covered rather than whole screens because they are where
/// the fixed heights and single-line labels live; a screen inherits their
/// behaviour.
Widget _scaled(Widget child, {double scale = 2.0, Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      // Phone width, not the 800x600 test default: text wrapping at 200%
      // only bites at realistic widths.
      child: Scaffold(
        body: SizedBox(
          width: 390,
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('Font scale 200%', () {
    testWidgets('buttons do not overflow their pill', (tester) async {
      await tester.pumpWidget(
        _scaled(
          Column(
            children: [
              SaButton(label: 'Send emergency alert', onPressed: () {}),
              const SizedBox(height: 8),
              SaButton(
                label: 'Cancel',
                variant: SaButtonVariant.secondary,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('text fields keep their label and helper text', (tester) async {
      await tester.pumpWidget(
        _scaled(
          const SaTextField(
            label: 'Email address',
            errorText: 'We could not reach that address — check it and try again.',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.text('Email address'), findsOneWidget);
    });

    testWidgets('cards absorb long content at 200%', (tester) async {
      await tester.pumpWidget(
        _scaled(
          Column(
            children: [
              const SaCard(child: Text('A safety summary that runs to some length.')),
              const SizedBox(height: 8),
              const SaStatCard(value: '47', label: 'Incidents recorded'),
              const SizedBox(height: 8),
              SaContactCard(
                name: 'Anika Sharma',
                relationship: 'Sister',
                priority: 1,
                onTap: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('alert card survives a long summary', (tester) async {
      await tester.pumpWidget(
        _scaled(
          SaAlertCard(
            title: 'Elevated motion detected near Elm Street',
            timestamp: '2h ago',
            level: ThreatLevel.elevated,
            summary:
                'A sudden acceleration spike was followed by an unusual gait '
                'pattern. SafeHer raised the threat score and prepared an alert.',
            onTap: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('threat chip and battery bar hold their shape', (tester) async {
      await tester.pumpWidget(
        _scaled(
          const Column(
            children: [
              SaThreatChip(level: ThreatLevel.danger),
              SizedBox(height: 8),
              SaBatteryBar(percent: 0.17),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('empty state stays readable', (tester) async {
      await tester.pumpWidget(
        _scaled(
          SaEmptyState(
            title: 'Nothing to report',
            body: 'No incidents have been recorded on your account.',
            ctaLabel: 'Refresh',
            onCtaTap: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('bottom nav labels do not overflow their 56dp tabs', (tester) async {
      // The tightest constraint in the app: four fixed-width tabs around a
      // centre FAB, each with a label that only shows when active.
      await tester.pumpWidget(
        _scaled(
          SaBottomNavBar(
            currentTab: SaNavTab.dashboard,
            onTabSelected: (_) {},
            onSosTap: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });

    testWidgets('heat grid is size-driven, not text-driven', (tester) async {
      await tester.pumpWidget(
        _scaled(
          const SaHeatGrid(
            cells: [
              SaHeatCell(lat: 17.38, lng: 78.48, weight: 4),
              SaHeatCell(lat: 17.41, lng: 78.47, weight: 1),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('light mode fares the same as dark', (tester) async {
      await tester.pumpWidget(
        _scaled(
          Column(
            children: [
              SaButton(label: 'Send emergency alert', onPressed: () {}),
              const SizedBox(height: 8),
              const SaStatCard(value: '47', label: 'Incidents recorded'),
            ],
          ),
          brightness: Brightness.light,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('holds at 300%, past the SRS floor', (tester) async {
      // Android's accessibility settings go beyond 200%. Not an SRS
      // requirement, but a component that survives 300% will not be the one
      // that breaks at 200% after an unrelated copy change.
      await tester.pumpWidget(
        _scaled(
          Column(
            children: [
              SaButton(label: 'Send emergency alert', onPressed: () {}),
              const SizedBox(height: 8),
              const SaThreatChip(level: ThreatLevel.caution),
            ],
          ),
          scale: 3.0,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });
  });

  group('Dashboard models at scale', () {
    test('threat day severity is a max, not an average', () {
      // Guards a subtle regression: a day with one critical incident must
      // never read calmer than a day with three low ones.
      final critical = ThreatDay(
        date: DateTime(2026, 8, 15),
        total: 4,
        counts: const {'critical': 1, 'low': 3},
      );
      final lowOnly = ThreatDay(
        date: DateTime(2026, 8, 15),
        total: 3,
        counts: const {'low': 3},
      );

      expect(critical.level, ThreatLevel.danger);
      expect(lowOnly.level, ThreatLevel.caution);
    });

    test('a day with no incidents is the only safe day', () {
      final quiet = ThreatDay(date: DateTime(2026, 8, 15), total: 0, counts: const {});
      final unlabelled = ThreatDay(
        date: DateTime(2026, 8, 15),
        total: 1,
        counts: const {'unknown': 1},
      );

      expect(quiet.level, ThreatLevel.safe);
      expect(unlabelled.level, ThreatLevel.caution);
    });
  });
}
