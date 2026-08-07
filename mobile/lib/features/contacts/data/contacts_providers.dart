import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_notifier.dart';
import '../../../core/offline/offline_queue_providers.dart';
import '../domain/contacts_repository.dart';
import '../domain/models/contact.dart';
import 'contacts_repository_mock.dart';
import 'contacts_repository_remote.dart';

part 'contacts_providers.g.dart';

@riverpod
ContactsRepository contactsRepository(Ref ref) {
  if (AppConfig.useMockApi) return ContactsRepositoryMock();
  return ContactsRepositoryRemote();
}

/// The single source of truth for the app's emergency contacts — Settings,
/// Emergency, Search, and Profile all watch this instead of keeping their
/// own copies, so adding/removing/reordering a contact anywhere is
/// immediately reflected everywhere.
///
/// Mutations made while offline apply optimistically to local state and
/// are queued (see `OfflineQueueService`) rather than failing outright —
/// they replay automatically the next time connectivity comes back.
@Riverpod(keepAlive: true)
class ContactsNotifier extends _$ContactsNotifier {
  @override
  Future<List<Contact>> build() {
    _registerOfflineHandlers();
    return ref.watch(contactsRepositoryProvider).getContacts();
  }

  void _registerOfflineHandlers() {
    final queue = ref.read(offlineQueueServiceProvider);
    queue.registerHandler('contacts.add', (payload) async {
      final repo = ref.read(contactsRepositoryProvider);
      final updated = await repo.addContact(payload['name'] as String, payload['relationship'] as String);
      state = AsyncData(updated);
    });
    queue.registerHandler('contacts.remove', (payload) async {
      final repo = ref.read(contactsRepositoryProvider);
      final updated = await repo.removeContact(payload['id'] as String);
      state = AsyncData(updated);
    });
  }

  bool get _isOffline => ref.read(connectivityNotifierProvider).valueOrNull == false;

  Future<void> addContact(String name, String relationship) async {
    final current = state.valueOrNull ?? const [];
    if (_isOffline) {
      final optimistic = Contact(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        relationship: relationship,
        priority: current.length + 1,
        confirmed: false,
      );
      state = AsyncData([...current, optimistic]);
      await ref.read(offlineQueueServiceProvider).enqueue('contacts.add', {'name': name, 'relationship': relationship});
      return;
    }
    state = AsyncData(await ref.read(contactsRepositoryProvider).addContact(name, relationship));
  }

  Future<void> removeContact(String id) async {
    if (_isOffline) {
      final current = state.valueOrNull ?? const [];
      state = AsyncData(current.where((c) => c.id != id).toList());
      await ref.read(offlineQueueServiceProvider).enqueue('contacts.remove', {'id': id});
      return;
    }
    state = AsyncData(await ref.read(contactsRepositoryProvider).removeContact(id));
  }

  Future<void> reorder(List<Contact> newOrder) async {
    state = AsyncData(newOrder);
    if (_isOffline) return; // Reordering doesn't queue: it's re-applied from getContacts() next sync.
    state = AsyncData(await ref.read(contactsRepositoryProvider).reorderContacts(newOrder));
  }
}
