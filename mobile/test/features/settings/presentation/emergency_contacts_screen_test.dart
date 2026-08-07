import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';
import 'package:safeher_app/features/settings/presentation/emergency_contacts_screen.dart';

import '../../../test_utils/offline_test_overrides.dart';

List<Contact> _sampleContacts() => [
  const Contact(id: '1', name: 'Anika Sharma', relationship: 'Sister', priority: 1, confirmed: true),
  const Contact(id: '2', name: 'Rahul Verma', relationship: 'Partner', priority: 2, confirmed: true),
];

class _FakeContactsRepository implements ContactsRepository {
  _FakeContactsRepository({this.shouldFail = false, List<Contact>? initialContacts})
    : _contacts = initialContacts ?? _sampleContacts();
  final bool shouldFail;
  final List<Contact> _contacts;
  var _nextId = 3;

  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> addContact(String name, String relationship) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _contacts.add(
      Contact(id: '${_nextId++}', name: name, relationship: relationship, priority: _contacts.length + 1, confirmed: false),
    );
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> removeContact(String id) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _contacts.removeWhere((c) => c.id == id);
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _contacts
      ..clear()
      ..addAll(newOrder);
    return List.unmodifiable(_contacts);
  }
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/settings/contacts',
    routes: [
      GoRoute(path: '/settings/contacts', builder: (context, state) => const EmergencyContactsScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const Scaffold(body: Text('settings-stub'))),
    ],
  );
}

Widget _harness({Brightness brightness = Brightness.dark, ContactsRepository? repo}) {
  return ProviderScope(
    overrides: [
      contactsRepositoryProvider.overrideWithValue(repo ?? _FakeContactsRepository()),
      ...offlineTestOverrides(),
    ],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

void main() {
  group('EmergencyContactsScreen', () {
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
      expect(find.text('Anika Sharma'), findsOneWidget);
      expect(find.text('Rahul Verma'), findsOneWidget);
    });

    testWidgets('renders_empty_state (no contacts)', (tester) async {
      final repo = _FakeContactsRepository(initialContacts: []);
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('No emergency contacts yet'), findsOneWidget);
    });

    testWidgets('renders_empty_state (error + retry)', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeContactsRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load your contacts"), findsOneWidget);
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

    testWidgets('navigation_actions_work: back button returns to settings', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('settings-stub'), findsOneWidget);
    });

    testWidgets('swiping a contact removes it', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.drag(find.text('Rahul Verma'), const Offset(-500, 0));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Rahul Verma'), findsNothing);
      expect(find.text('Anika Sharma'), findsOneWidget);
    });

    testWidgets('adding a contact via the sheet appends it to the list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Add contact'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Add Emergency Contact'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Kabir Rao');
      await tester.enterText(fields.at(1), 'Neighbor');
      await tester.pump();

      await tester.tap(find.text('Add Contact'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Kabir Rao'), findsOneWidget);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'emergency_contacts_screen_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'emergency_contacts_screen_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
