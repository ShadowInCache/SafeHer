import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/search/data/search_providers.dart';
import 'package:safeher_app/features/search/domain/models/search_result.dart';
import 'package:safeher_app/features/search/domain/search_repository.dart';
import 'package:safeher_app/features/search/presentation/search_screen.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

SearchIndex _sampleIndex() => const SearchIndex(
  incidents: [
    SearchIncidentResult(
      id: '1',
      date: 'Aug 2',
      type: 'Elevated motion detected',
      level: ThreatLevel.elevated,
      summarySnippet: 'Sudden acceleration spike near Elm Street.',
    ),
  ],
  contacts: [SearchContactResult(id: '1', name: 'Anika Sharma', relationship: 'Sister', priority: 1)],
  devices: [
    SearchDeviceResult(id: 'ring', name: 'Smart Ring', batteryPercent: 0.82, signalStrength: 3, isOnline: true),
  ],
);

class _FakeSearchRepository implements SearchRepository {
  _FakeSearchRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<SearchIndex> getSearchIndex() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleIndex();
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(
        path: '/reports/:id',
        builder: (context, state) => Scaffold(body: Text('report-${state.pathParameters['id']}-stub')),
      ),
      GoRoute(path: '/profile', builder: (context, state) => const Scaffold(body: Text('profile-stub'))),
      GoRoute(
        path: '/devices/:id',
        builder: (context, state) => Scaffold(body: Text('device-${state.pathParameters['id']}-stub')),
      ),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, SearchRepository? repo}) {
  return ProviderScope(
    overrides: [searchRepositoryProvider.overrideWithValue(repo ?? _FakeSearchRepository())],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('SearchScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data: empty query shows prompt', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Search SafeHer'), findsOneWidget);
    });

    testWidgets('typing a query filters and shows matching sections', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), 'Anika');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      // "Contacts" appears both as the filter chip label and the results
      // section header once a contact matches.
      expect(find.text('Contacts'), findsNWidgets(2));
      expect(find.text('Anika Sharma'), findsOneWidget);
      expect(find.text('Incidents'), findsOneWidget); // chip label only, no section header
    });

    testWidgets('no results shows empty state with query', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), 'zzzznomatch');
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('No results'), findsOneWidget);
    });

    testWidgets('category chip filters results to that category', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // The chip row scrolls horizontally, so "Devices" (the last chip)
      // may start outside the visible/tappable viewport. At this point
      // (empty query, category still "all") "Devices" only appears once,
      // as the chip label — no results section is showing yet.
      await tester.ensureVisible(find.text('Devices'));
      await tester.pump();
      await tester.tap(find.text('Devices'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // "Devices" appears both as the filter chip label and the section header.
      expect(find.text('Devices'), findsNWidgets(2));
      expect(find.text('Smart Ring'), findsOneWidget);
      expect(find.text('Incidents'), findsOneWidget); // chip label only
      expect(find.text('Contacts'), findsOneWidget); // chip label only
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeSearchRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load search"), findsOneWidget);
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

    testWidgets('navigation_actions_work: incident result navigates to report detail', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'motion');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Elevated motion detected'));
      await tester.pumpAndSettle();
      expect(find.text('report-1-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: device result navigates to device detail', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), 'ring');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Smart Ring'));
      await tester.pumpAndSettle();
      expect(find.text('device-ring-stub'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(
        tester,
        'search_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(
        tester,
        'search_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
