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
import 'package:safeher_app/features/settings/presentation/emergency_contacts_screen.dart';

import '../../../test_utils/offline_test_overrides.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

List<Contact> _sampleContacts() => [
  const Contact(id: '1', name: 'Anika Sharma', phone: '+15550101001', relationship: 'Sister', priority: 1, confirmed: true),
  const Contact(id: '2', name: 'Rahul Verma', phone: '+15550101002', relationship: 'Partner', priority: 2, confirmed: true),
];

class _FakeContactsRepository implements ContactsRepository {
  /// Defaults to "everything works" so existing tests are unaffected by the
  /// unreachable-contact warning; the settings tests override it.
  AlertChannels channels = const AlertChannels(sms: true, email: true, push: true);

  @override
  Future<AlertChannels> getAlertChannels() async => channels;

  @override
  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    final index = _contacts.indexWhere((c) => c.id == id);
    if (index != -1) {
      final existing = _contacts[index];
      _contacts[index] = Contact(
        id: existing.id,
        name: name ?? existing.name,
        phone: phone ?? existing.phone,
        relationship: relationship ?? existing.relationship,
        priority: existing.priority,
        confirmed: existing.confirmed,
        email: (email != null && email.isNotEmpty) ? email : existing.email,
      );
    }
    return List.unmodifiable(_contacts);
  }

  _FakeContactsRepository({this.shouldFail = false, List<Contact>? initialContacts})
    : _contacts = List.of(initialContacts ?? _sampleContacts());
  final bool shouldFail;
  final List<Contact> _contacts;
  var _nextId = 3;

  /// Read-only view for assertions.
  List<Contact> get contacts => List.unmodifiable(_contacts);

  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return List.unmodifiable(_contacts);
  }

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
    _contacts.add(
      Contact(
        id: '${_nextId++}',
        name: name,
        phone: phone,
        relationship: relationship,
        priority: _contacts.length + 1,
        confirmed: false,
        email: email,
      ),
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
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
    ),
  );
}

/// Opens sequence for a modal sheet: one frame to insert the route, then
/// its entrance animation. A single 300ms pump leaves the sheet still fully
/// below the viewport, where its controls cannot be tapped.
/// The contacts future resolves first; only then does `_ContactsList` mount
/// and begin watching `alertChannelsProvider`, so its answer lands a frame
/// later again.
Future<void> _settleChannels(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
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
      final repo = _FakeContactsRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Add contact'));
      await _settleSheet(tester);
      expect(find.text('Add Emergency Contact'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Kabir Rao');
      await tester.enterText(fields.at(1), '+15550101099');
      await tester.enterText(fields.at(2), 'Neighbor');
      await tester.pump();

      await tester.ensureVisible(find.text('Add Contact'));
      await tester.pump();
      await tester.tap(find.text('Add Contact'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // Asserted against the repository, not `find.text`: the name is also
      // sitting in the text field it was typed into, so a find-by-text here
      // passes whether or not the contact was ever saved.
      expect(repo.contacts.map((c) => c.name), contains('Kabir Rao'));
    });

    testWidgets('an email address reaches the repository', (tester) async {
      // Email is the only emergency channel this project can run for free
      // (OneSignal's free tier), so a contact saved without one can only be
      // reached if SMS credit exists. The field has to actually work.
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Add contact'));
      await _settleSheet(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Kabir Rao');
      await tester.enterText(fields.at(1), '+15550101099');
      await tester.enterText(fields.at(2), 'Neighbor');
      await tester.enterText(fields.at(3), 'kabir@example.com');
      await tester.pump();

      await tester.ensureVisible(find.text('Add Contact'));
      await tester.pump();
      await tester.tap(find.text('Add Contact'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      final saved = repo.contacts.firstWhere((c) => c.name == 'Kabir Rao');
      expect(saved.email, 'kabir@example.com');
      expect(saved.hasEmail, isTrue);
    });

    testWidgets('a malformed email blocks saving rather than being sent', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Add contact'));
      await _settleSheet(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Kabir Rao');
      await tester.enterText(fields.at(1), '+15550101099');
      await tester.enterText(fields.at(2), 'Neighbor');
      await tester.enterText(fields.at(3), 'not-an-email');
      await tester.pump();

      expect(find.text('That doesn’t look like an email address.'), findsOneWidget);

      await tester.ensureVisible(find.text('Add Contact'));
      await tester.pump();
      await tester.tap(find.text('Add Contact'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      // Against the repository, not the screen: 'Kabir Rao' is sitting in
      // the name field either way.
      expect(repo.contacts.map((c) => c.name), isNot(contains('Kabir Rao')));
    });

    testWidgets('an omitted email is saved as null, not an empty string', (tester) async {
      // The backend validates this as an EmailStr; an empty string is a
      // 422, so "no email" has to travel as an absent field.
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository();
      await tester.pumpWidget(_harness(repo: repo));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Add contact'));
      await _settleSheet(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Kabir Rao');
      await tester.enterText(fields.at(1), '+15550101099');
      await tester.enterText(fields.at(2), 'Neighbor');
      await tester.pump();

      await tester.ensureVisible(find.text('Add Contact'));
      await tester.pump();
      await tester.tap(find.text('Add Contact'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));

      final saved = repo.contacts.firstWhere((c) => c.name == 'Kabir Rao');
      expect(saved.email, isNull);
    });

    testWidgets('warns when an SOS cannot reach a contact', (tester) async {
      // The situation this whole feature exists for: SMS costs money and is
      // unconfigured, so a contact saved with only a phone number cannot be
      // reached at all. Showing them as a normal saved contact would let a
      // user believe her sister will be alerted.
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository(
        initialContacts: const [
          Contact(
            id: '1',
            name: 'No Email',
            phone: '+15550101000',
            relationship: 'Sister',
            priority: 1,
            confirmed: true,
          ),
        ],
      )..channels = const AlertChannels(sms: false, email: true, push: false);

      await tester.pumpWidget(_harness(repo: repo));
      await _settleChannels(tester);

      expect(find.text('An alert can’t reach this contact'), findsOneWidget);
      expect(find.text('Add an email address'), findsOneWidget);
    });

    testWidgets('a contact with an email is not flagged', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository(
        initialContacts: const [
          Contact(
            id: '1',
            name: 'Has Email',
            phone: '+15550101000',
            relationship: 'Sister',
            priority: 1,
            confirmed: true,
            email: 'has@example.com',
          ),
        ],
      )..channels = const AlertChannels(sms: false, email: true, push: false);

      await tester.pumpWidget(_harness(repo: repo));
      await _settleChannels(tester);

      expect(find.text('An alert can’t reach this contact'), findsNothing);
    });

    testWidgets('no warning while SMS is available', (tester) async {
      // With SMS working a phone number is enough, and a warning here would
      // be false. A warning only helps if it is rare and true.
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository(
        initialContacts: const [
          Contact(
            id: '1',
            name: 'No Email',
            phone: '+15550101000',
            relationship: 'Sister',
            priority: 1,
            confirmed: true,
          ),
        ],
      )..channels = const AlertChannels(sms: true, email: true, push: false);

      await tester.pumpWidget(_harness(repo: repo));
      await _settleChannels(tester);

      expect(find.text('An alert can’t reach this contact'), findsNothing);
    });

    testWidgets('editing a contact adds the email that makes it reachable', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _FakeContactsRepository(
        initialContacts: const [
          Contact(
            id: '1',
            name: 'No Email',
            phone: '+15550101000',
            relationship: 'Sister',
            priority: 1,
            confirmed: true,
          ),
        ],
      )..channels = const AlertChannels(sms: false, email: true, push: false);

      await tester.pumpWidget(_harness(repo: repo));
      await _settleChannels(tester);

      await tester.tap(find.text('Add an email address'));
      await _settleSheet(tester);

      // The sheet opens in edit mode, prefilled — the user should only have
      // to type the missing field.
      expect(find.text('Edit Emergency Contact'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(3), 'sister@example.com');
      await tester.pump();
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pump();
      await tester.tap(find.text('Save Changes'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));

      expect(repo.contacts.single.email, 'sister@example.com');
      expect(find.text('An alert can’t reach this contact'), findsNothing);
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
