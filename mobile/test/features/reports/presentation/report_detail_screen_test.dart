import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/reports/data/reports_providers.dart';
import 'package:safeher_app/features/reports/domain/models/evidence_item.dart';
import 'package:safeher_app/features/reports/domain/models/gps_breadcrumb.dart';
import 'package:safeher_app/features/reports/domain/models/report_detail.dart';
import 'package:safeher_app/features/reports/domain/models/report_summary.dart';
import 'package:safeher_app/features/reports/domain/models/timeline_event.dart';
import 'package:safeher_app/features/reports/domain/reports_repository.dart';
import 'package:safeher_app/features/reports/presentation/report_detail_screen.dart';
import 'package:safeher_app/shared/components/charts/sa_motion_chart.dart';
import 'package:safeher_app/shared/components/icons/sa_icon.dart';
import 'package:safeher_app/shared/models/threat_level.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

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
  timeline: const [
    TimelineEvent(
      type: TimelineEventType.sensorEvent,
      title: 'Sensor anomaly detected',
      description: 'Motion sensor crossed baseline.',
      timestamp: 'T+00:00',
    ),
    TimelineEvent(
      type: TimelineEventType.aiDetection,
      title: 'AI classification: Elevated motion',
      description: 'Flagged for review.',
      timestamp: 'T+00:01',
      confidence: 0.82,
    ),
  ],
  evidence: const [
    EvidenceItem(id: 'v1', type: EvidenceType.video, url: '', durationLabel: '0:18'),
    EvidenceItem(id: 'a1', type: EvidenceType.audio, url: ''),
    EvidenceItem(id: 'p1', type: EvidenceType.photo, url: ''),
  ],
  gpsBreadcrumbs: const [
    GpsBreadcrumb(latitude: 37.7749, longitude: -122.4194, timestamp: 'T+00:00'),
    GpsBreadcrumb(latitude: 37.7755, longitude: -122.4188, timestamp: 'T+00:03'),
  ],
  chainOfCustodyHash: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567',
);

class _FakeReportsRepository implements ReportsRepository {
  var exportCalls = <String>[];
  var shareCalls = <String>[];

  /// Set to make both actions fail, as a network error would.
  bool actionsFail = false;

  @override
  Future<Uint8List> exportPdf(String incidentId) async {
    exportCalls.add(incidentId);
    if (actionsFail) throw Exception('export failed');
    return Uint8List.fromList('%PDF-1.4 fake'.codeUnits);
  }

  @override
  Future<String> createShareLink(String incidentId) async {
    shareCalls.add(incidentId);
    if (actionsFail) throw Exception('share failed');
    return 'https://example.invalid/api/v1/share/token-$incidentId';
  }

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
      await tester.scrollUntilVisible(find.text('Event Timeline'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Sensor anomaly detected'), findsOneWidget);
      expect(find.text('82% confidence'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Location Trail'), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('Location Trail'), 300, scrollable: find.byType(Scrollable).first);
      await tester.scrollUntilVisible(find.text('Export PDF'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Share Secure Link'), findsOneWidget);
      expect(find.textContaining('Chain of custody: abcdef0123456789'), findsOneWidget);
    });

    testWidgets('tapping a video evidence tile opens the player sheet with graceful fallback', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Location Trail'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('0:18'), findsOneWidget);
      await tester.tap(find.text('0:18'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Evidence not available'), findsOneWidget);
    });

    testWidgets('tapping the photo evidence tile opens the full-screen viewer', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Location Trail'), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byWidgetPredicate((w) => w is SaIcon && w.glyph == SaIconGlyph.eye));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Photo not available'), findsOneWidget);
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

    testWidgets('Export PDF actually fetches a report', (tester) async {
      // Regression: this button was a toast reading "Preparing PDF export…"
      // and nothing else. A message claiming an action that did not happen
      // is worse here than no button at all — a user who believes she has a
      // copy of her own evidence stops trying to get one.
      final repo = _FakeReportsRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
        find.text('Export PDF'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export PDF'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.exportCalls, ['1']);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Share Secure Link actually mints one', (tester) async {
      // Clipboard is a platform channel with no handler in the test
      // binding, so the await never completes and the code never reaches
      // its toast. Mocked rather than worked around, because the product
      // behaviour under test is "link minted, then confirmed".
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      // The same button used to claim "Secure link copied" when no link had
      // been created and the clipboard was untouched.
      final repo = _FakeReportsRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
        find.text('Share Secure Link'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Share Secure Link'));
      // One frame to run the async handler, then the toast's slide-in.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.shareCalls, ['1']);
      // Either title is correct: the clipboard is a platform channel and
      // whether it answers in a test binding is not what this test is for.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == 'Link copied' || w.data == 'Link created'),
        ),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('a failed export says so instead of going quiet', (tester) async {
      final repo = _FakeReportsRepository()..actionsFail = true;
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.scrollUntilVisible(
        find.text('Export PDF'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Export PDF'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Couldn’t export the report'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 300));
    });

  });
}
