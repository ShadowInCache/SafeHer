import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/contacts_repository.dart';
import '../domain/models/contact.dart';
import 'contacts_repository_mock.dart';

part 'contacts_providers.g.dart';

@riverpod
ContactsRepository contactsRepository(Ref ref) {
  return ContactsRepositoryMock();
}

/// The single source of truth for the app's emergency contacts — Settings,
/// Emergency, Search, and Profile all watch this instead of keeping their
/// own copies, so adding/removing/reordering a contact anywhere is
/// immediately reflected everywhere.
@riverpod
class ContactsNotifier extends _$ContactsNotifier {
  @override
  Future<List<Contact>> build() {
    return ref.watch(contactsRepositoryProvider).getContacts();
  }

  Future<void> addContact(String name, String relationship) async {
    state = AsyncData(await ref.read(contactsRepositoryProvider).addContact(name, relationship));
  }

  Future<void> removeContact(String id) async {
    state = AsyncData(await ref.read(contactsRepositoryProvider).removeContact(id));
  }

  Future<void> reorder(List<Contact> newOrder) async {
    state = AsyncData(newOrder);
    state = AsyncData(await ref.read(contactsRepositoryProvider).reorderContacts(newOrder));
  }
}
