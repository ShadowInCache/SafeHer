import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/alert_channels.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';
import 'package:safeher_app/features/devices/data/device_providers.dart';
import 'package:safeher_app/features/devices/domain/device_repository.dart';
import 'package:safeher_app/features/devices/domain/models/device_detail.dart';
import 'package:safeher_app/features/reports/data/reports_providers.dart';
import 'package:safeher_app/features/reports/domain/models/report_detail.dart';
import 'package:safeher_app/features/reports/domain/models/report_summary.dart';
import 'package:safeher_app/features/reports/domain/reports_repository.dart';
import 'package:safeher_app/features/search/presentation/search_screen.dart';
import 'package:safeher_app/shared/models/threat_level.dart';

import '../../../test_utils/offline_test_overrides.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _FakeReportsRepository implements ReportsRepository {
  _FakeReportsRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<List<ReportSummary>> getReports() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return const [
      ReportSummary(
        id: '1',
        date: 'Aug 2',
        type: 'Elevated motion detected',
        level: ThreatLevel.elevated,
        summarySnippet: 'Sudden acceleration spike near Elm Street.',
      ),
    ];
  }

  @override
  Future<ReportDetail> getReportDetail(String id) => throw UnimplementedError();
}

class _FakeContactsRepository implements ContactsRepository {
  var verificationSends = <String>[];
  var verificationCodes = <String>[];

  /// Set to make [confirmVerificationCode] throw, as a wrong code does.
  bool verificationFails = false;

  @override
  Future<bool> sendVerificationCode(String id) async {
    verificationSends.add(id);
    return false;
  }

  @override
  Future<List<Contact>> confirmVerificationCode(String id, String code) async {
    verificationCodes.add(code);
    if (verificationFails) throw Exception('wrong code');
    return getContacts();
  }

  /// Defaults to "everything works" so existing tests are unaffected by the
  /// unreachable-contact warning; the settings tests override it.
  AlertChannels channels = const AlertChannels(sms: true, email: true, push: true);

  @override
  Future<AlertChannels> getAlertChannels() async => channels;

  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async => getContacts();

  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return const [Contact(id: '1', name: 'Anika Sharma', phone: '+15550101000', relationship: 'Sister', priority: 1, confirmed: true)];
  }

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) => throw UnimplementedError();

  @override
  Future<List<Contact>> removeContact(String id) => throw UnimplementedError();

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) => throw UnimplementedError();
}

class _FakeDeviceRepository implements DeviceRepository {
  @override
  Future<List<DeviceDetail>> getDevices() async {
    await Future.delayed(const Duration(milliseconds: 50));
    return const [
      DeviceDetail(
        id: 'ring',
        name: 'Smart Ring',
        type: DeviceType.ring,
        isOnline: true,
        batteryPercent: 0.82,
        batteryHoursRemaining: 36,
        signalStrength: 3,
        firmwareVersion: 'v2.4.1',
        updateAvailable: false,
        sensors: SensorReading(accelG: 1.02, gyroDps: 4.3, flexPercent: 0),
      ),
    ];
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
      GoRoute(path: '/reports', builder: (context, state) => const Scaffold(body: Text('reports-stub'))),
      GoRoute(
        path: '/reports/:id',
        builder: (context, state) => Scaffold(body: Text('report-${state.pathParameters['id']}-stub')),
      ),
      GoRoute(
        path: '/settings/contacts',
        builder: (context, state) => const Scaffold(body: Text('settings-contacts-stub')),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const Scaffold(body: Text('settings-stub'))),
      GoRoute(path: '/devices', builder: (context, state) => const Scaffold(body: Text('devices-stub'))),
      GoRoute(
        path: '/devices/:id',
        builder: (context, state) => Scaffold(body: Text('device-${state.pathParameters['id']}-stub')),
      ),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, ReportsRepository? reportsRepo}) {
  return ProviderScope(
    overrides: [
      reportsRepositoryProvider.overrideWithValue(reportsRepo ?? _FakeReportsRepository()),
      contactsRepositoryProvider.overrideWithValue(_FakeContactsRepository()),
      deviceRepositoryProvider.overrideWithValue(_FakeDeviceRepository()),
      ...offlineTestOverrides(),
    ],
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
  group('SearchScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('renders_with_data: empty query shows quick access grid', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Quick Access'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Contacts'), findsWidgets);
      expect(find.text('Devices'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
    });

    testWidgets('tapping a Quick Access card navigates directly', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.text('reports-stub'), findsOneWidget);
    });

    testWidgets('recent searches appear as chips and re-run the search on tap', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ring');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.bySemanticsLabel('Recent search: ring'), findsNothing);
      // Let the 250ms debounce actually settle (and commit "ring" to
      // recent searches) before clearing the field — clearing too early
      // would cancel the pending timer instead of letting it fire.
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('ring'), findsOneWidget);

      await tester.tap(find.text('ring'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Smart Ring'), findsOneWidget);
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
      // (empty query, category still "all") "Devices" appears twice — the
      // filter chip and the Quick Access grid card — the chip is first in
      // paint order since it's above the results/empty-state area.
      await tester.ensureVisible(find.text('Devices').first);
      await tester.pump();
      await tester.tap(find.text('Devices').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // "Devices" appears both as the filter chip label and the section header.
      expect(find.text('Devices'), findsNWidgets(2));
      expect(find.text('Smart Ring'), findsOneWidget);
      expect(find.text('Incidents'), findsOneWidget); // chip label only
      expect(find.text('Contacts'), findsOneWidget); // chip label only
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(reportsRepo: _FakeReportsRepository(shouldFail: true)));
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
