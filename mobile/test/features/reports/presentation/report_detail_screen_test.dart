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
import 'package:safeher_app/features/reports/presentation/report_detail_screen.dart';
import 'package:safeher_app/shared/components/charts/sa_motion_chart.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

ReportDetail _sampleDetail(String id) => ReportDetail(
  id: id,
  date: 'Aug 2',
  time: '14:30',
  type: 'Elevated motion detected',
  level: ThreatLevel.elevated,
  fullSummary: 'Sudden acceleration spike near Elm Street lasting 4 seconds.',
  locationLabel: 'Elm Street, near 5th Ave',
  waveform: List.generate(64, (i) => 0.2 + (i % 8) * 0.05),
  motionSamples: List.generate(20, (i) => MotionSample(x: i * 0.1, y: 0.2, z: 0.1)),
  motionEvents: const [MotionEventPin(sampleIndex: 5, label: 'Peak event', timestamp: 'T+00:04')],
);

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<List<ReportSummary>> getReports() => throw UnimplementedError();

  @override
  Future<ReportDetail> getReportDetail(String id) async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleDetail(id);
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/reports/1',
    routes: [
      GoRoute(
        path: '/reports/:id',
        builder: (context, state) => ReportDetailScreen(reportId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/reports', builder: (context, state) => const Scaffold(body: Text('reports-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, ReportsRepository? repo}) {
  return ProviderScope(
    overrides: [reportsRepositoryProvider.overrideWithValue(repo ?? _FakeReportsRepository())],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('ReportDetailScreen', () {
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
      expect(find.text('Elevated motion detected'), findsOneWidget);
      expect(find.textContaining('Aug 2'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Elm Street, near 5th Ave'), findsOneWidget);
      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Motion'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeReportsRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load this report"), findsOneWidget);
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

    testWidgets('navigation_actions_work: back button returns to reports list', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('reports-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'report_detail_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'report_detail_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
