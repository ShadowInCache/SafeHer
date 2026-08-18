import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/alert_channels.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';

import '../../test_utils/offline_test_overrides.dart';

/// One account must never see another account's data.
///
/// Several providers are `@Riverpod(keepAlive: true)` so their state survives
/// navigation — right for a live BLE link, wrong for anything belonging to a
/// person. Nothing invalidated them on sign-out, so the cached list simply
/// stayed: sign out, sign in as someone else, and the previous account's
/// emergency contacts were on screen. Their names, their numbers, their email
/// addresses.
///
/// Found on a real device by signing into a second account. The server was
/// never wrong — every row was correctly scoped the whole time — which is
/// exactly why no backend test and no single-user widget test could see it.
class _AccountScopedContacts implements ContactsRepository {
  _AccountScopedContacts(this.contacts);

  /// Stands in for "whoever is signed in right now".
  List<Contact> contacts;
  int fetches = 0;

  @override
  Future<List<Contact>> getContacts() async {
    fetches++;
    return contacts;
  }

  @override
  Future<AlertChannels> getAlertChannels() async =>
      const AlertChannels(sms: false, email: true, push: false);

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) async => getContacts();

  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async => getContacts();

  @override
  Future<bool> sendVerificationCode(String id) async => true;

  @override
  Future<List<Contact>> confirmVerificationCode(String id, String code) async =>
      getContacts();

  @override
  Future<List<Contact>> removeContact(String id) async => getContacts();

  @override
  Future<List<Contact>> reorderContacts(List<Contact> ordered) async => ordered;
}

Contact _contact(String id, String name) => Contact(
      id: id,
      name: name,
      phone: '+910000000000',
      relationship: 'Family',
      priority: 1,
      confirmed: false,
    );

void main() {
  late _AccountScopedContacts repository;
  late ProviderContainer container;

  setUp(() {
    repository = _AccountScopedContacts([_contact('a1', 'Amma')]);
    container = ProviderContainer(
      overrides: [
        contactsRepositoryProvider.overrideWithValue(repository),
        // ContactsNotifier.build() registers offline-queue handlers, so the
        // queue has to exist even though nothing here goes offline.
        ...offlineTestOverrides(),
      ],
    );
    addTearDown(container.dispose);
  });

  test('contacts stay cached across reads, which is what keepAlive is for', () async {
    // Worth keeping: a list this stable should not hit the network on every
    // screen change. The caching is not the bug — the missing reset was.
    await container.read(contactsNotifierProvider.future);
    await container.read(contactsNotifierProvider.future);

    expect(repository.fetches, 1);
  });

  test('a session reset drops the previous account\'s contacts', () async {
    final first = await container.read(contactsNotifierProvider.future);
    expect(first.single.name, 'Amma');

    // A different person signs in.
    repository.contacts = [_contact('b1', 'Ravi')];
    container.invalidate(contactsNotifierProvider);

    final second = await container.read(contactsNotifierProvider.future);

    expect(second.single.name, 'Ravi');
    expect(second.any((c) => c.name == 'Amma'), isFalse,
        reason: 'the signed-out account\'s contacts must not survive');
    expect(repository.fetches, 2);
  });

  test('without invalidation the stale list persists — the bug, reproduced', () async {
    // Reproduces the original defect so the fix has something to be measured
    // against. If the provider ever starts disposing on its own this fails,
    // and whoever removed the reset finds out from a test rather than from a
    // user seeing someone else's emergency contacts.
    final first = await container.read(contactsNotifierProvider.future);
    expect(first.single.name, 'Amma');

    repository.contacts = [_contact('b1', 'Ravi')];

    final second = await container.read(contactsNotifierProvider.future);

    expect(second.single.name, 'Amma', reason: 'still the old account, uninvalidated');
    expect(repository.fetches, 1);
  });
}
