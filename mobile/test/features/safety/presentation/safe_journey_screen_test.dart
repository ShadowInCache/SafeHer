import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safeher_app/core/location/location_providers.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';
import 'package:safeher_app/features/safety/data/safety_providers.dart';
import 'package:safeher_app/features/safety/domain/models/safe_journey.dart';
import 'package:safeher_app/features/safety/domain/models/safety_settings.dart';
import 'package:safeher_app/features/safety/presentation/safe_journey_screen.dart';

import '../../../test_utils/fake_location_service.dart';
import '../../../test_utils/fake_safety_repository.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _StubContactsRepository implements ContactsRepository {
  @override
  Future<List<Contact>> getContacts() async => const [
    Contact(
      id: 'c1',
      name: 'Asha',
      phone: '+911111111111',
      relationship: 'Sister',
      priority: 1,
      confirmed: true,
    ),
  ];

  @override
  Future<List<Contact>> addContact(String name, String phone, String relationship) async => const [];

  @override
  Future<List<Contact>> removeContact(String id) async => const [];

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) async => newOrder;
}

Widget _harness({required FakeJourneyRepository journeys, FakeSafetyRepository? safety}) {
  return ProviderScope(
    overrides: [
      journeyRepositoryProvider.overrideWithValue(journeys),
      // Auto-share off keeps these tests about the journey lifecycle rather
      // than the breadcrumb loop, which has its own coverage.
      safetyRepositoryProvider.overrideWithValue(
        safety ??
            FakeSafetyRepository(
              preferences: const SafetyPreferences.defaults().copyWith(
                journeyAutoShareLocation: false,
              ),
            ),
      ),
      contactsRepositoryProvider.overrideWithValue(_StubContactsRepository()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
    ],
    child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: AppTheme.dark,
      routerConfig: GoRouter(
        initialLocation: '/safety/journey',
        routes: [
          GoRoute(path: '/safety/journey', builder: (_, __) => const SafeJourneyScreen()),
          GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home-stub'))),
        ],
      ),
    ),
  );
}

SafeJourney _journey({
  JourneyStatus status = JourneyStatus.active,
  Duration remaining = const Duration(minutes: 20),
}) {
  final now = DateTime.now();
  return SafeJourney(
    id: 'journey-1',
    destinationLabel: 'Home',
    expectedDurationMinutes: 30,
    status: status,
    startedAt: now.subtract(const Duration(minutes: 10)),
    expectedArrivalAt: now.add(remaining),
    contactIds: const ['c1'],
  );
}

void main() {
  group('SafeJourneyScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness(journeys: FakeJourneyRepository()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('shows the start state when no journey is running', (tester) async {
      await tester.pumpWidget(_harness(journeys: FakeJourneyRepository()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No journey in progress'), findsOneWidget);
      expect(find.text('Start Safe Journey'), findsOneWidget);
    });

    testWidgets('shows the live journey with its destination and contacts', (tester) async {
      await tester.pumpWidget(
        _harness(journeys: FakeJourneyRepository(active: _journey())),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Journey active'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('1 contact'), findsOneWidget);
      expect(find.text("I've arrived safely"), findsOneWidget);
    });

    testWidgets('marks the journey as overdue once the deadline passes', (tester) async {
      await tester.pumpWidget(
        _harness(
          journeys: FakeJourneyRepository(
            active: _journey(status: JourneyStatus.overdue, remaining: const Duration(minutes: -5)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.textContaining('overdue'), findsWidgets);
    });

    testWidgets('check-in reaches the repository', (tester) async {
      final journeys = FakeJourneyRepository(active: _journey());
      await tester.pumpWidget(_harness(journeys: journeys));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Check in — still on my way'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(journeys.calls, contains('check-in:journey-1'));
      // Let the success toast's auto-dismiss timer finish.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('arriving reaches the repository and clears the active journey', (tester) async {
      final journeys = FakeJourneyRepository(active: _journey());
      await tester.pumpWidget(_harness(journeys: journeys));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text("I've arrived safely"));
      await tester.pump(const Duration(milliseconds: 300));

      expect(journeys.calls, contains('arrive:journey-1'));
      expect(find.text('No journey in progress'), findsOneWidget);
      // Let the success toast's auto-dismiss timer finish.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('an out-of-time journey asks the server to run the overdue policy', (tester) async {
      // The server re-checks the deadline itself; the app only reports that
      // its clock ran out.
      final journeys = FakeJourneyRepository(
        active: _journey(remaining: const Duration(seconds: -1)),
      );
      await tester.pumpWidget(_harness(journeys: journeys));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(journeys.calls, contains('escalate:journey-1'));
    });
  });
}
