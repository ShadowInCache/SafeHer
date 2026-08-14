import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/reports/data/reports_providers.dart';
import 'package:safeher_app/features/reports/domain/models/report_detail.dart';
import 'package:safeher_app/features/reports/domain/models/report_summary.dart';
import 'package:safeher_app/features/reports/domain/reports_repository.dart';
import 'package:safeher_app/features/reports/presentation/reports_list_screen.dart';
import 'package:safeher_app/shared/models/threat_level.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

List<ReportSummary> _sampleReports() => const [
  ReportSummary(
    id: '1',
    date: 'Aug 2',
    type: 'Elevated motion detected',
    level: ThreatLevel.elevated,
    summarySnippet: 'Sudden acceleration spike near Elm Street.',
  ),
  ReportSummary(
    id: '2',
    date: 'Aug 1',
    type: 'Routine check-in',
    level: ThreatLevel.safe,
    summarySnippet: 'All monitored signals within normal range.',
  ),
];

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository({this.shouldFail = false, this.empty = false});
  final bool shouldFail;
  final bool empty;

  @override
  Future<List<ReportSummary>> getReports() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return empty ? const [] : _sampleReports();
  }

  @override
  Future<ReportDetail> getReportDetail(String id) => throw UnimplementedError();
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/reports',
    routes: [
      GoRoute(path: '/reports', builder: (context, state) => const ReportsListScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(
        path: '/reports/:id',
        builder: (context, state) => Scaffold(body: Text('report-${state.pathParameters['id']}-stub')),
      ),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, ReportsRepository? repo}) {
  return ProviderScope(
    overrides: [reportsRepositoryProvider.overrideWithValue(repo ?? _FakeReportsRepository())],
    child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('ReportsListScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data (mocked repository)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Reports (2)'), findsOneWidget);
      expect(find.text('Elevated motion detected'), findsOneWidget);
      expect(find.text('Routine check-in'), findsOneWidget);
    });

    testWidgets('renders_empty_state (no reports)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeReportsRepository(empty: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('No reports yet'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeReportsRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your reports"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation_actions_work: back button returns to home', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: tapping a report navigates to detail', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Elevated motion detected'));
      await tester.pumpAndSettle();
      expect(find.text('report-1-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'reports_list_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'reports_list_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
