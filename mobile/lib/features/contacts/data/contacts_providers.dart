import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/connectivity/connectivity_notifier.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/offline/offline_queue_providers.dart';
import '../domain/contacts_repository.dart';
import '../domain/models/alert_channels.dart';
import '../domain/models/contact.dart';
import 'contacts_repository_mock.dart';
import 'contacts_repository_remote.dart';

part 'contacts_providers.g.dart';

@riverpod
ContactsRepository contactsRepository(Ref ref) {
  if (AppConfig.useMockApi) return ContactsRepositoryMock();
  return ContactsRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

/// Which emergency channels the server can deliver on.
///
/// Falls back to optimistic on failure: a wrongly-shown "can't be reached"
/// warning would train users to ignore a warning that only helps if it is
/// rare and true.
@riverpod
Future<AlertChannels> alertChannels(Ref ref) async {
  try {
    return await ref.watch(contactsRepositoryProvider).getAlertChannels();
  } catch (_) {
    return const AlertChannels.optimistic();
  }
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
      final updated = await repo.addContact(
        payload['name'] as String,
        payload['phone'] as String,
        payload['relationship'] as String,
        email: payload['email'] as String?,
      );
      state = AsyncData(updated);
    });
    queue.registerHandler('contacts.update', (payload) async {
      final repo = ref.read(contactsRepositoryProvider);
      final updated = await repo.updateContact(
        payload['id'] as String,
        name: payload['name'] as String?,
        phone: payload['phone'] as String?,
        relationship: payload['relationship'] as String?,
        email: payload['email'] as String?,
      );
      state = AsyncData(updated);
    });
    queue.registerHandler('contacts.remove', (payload) async {
      final repo = ref.read(contactsRepositoryProvider);
      final updated = await repo.removeContact(payload['id'] as String);
      state = AsyncData(updated);
    });
  }

  bool get _isOffline => ref.read(connectivityNotifierProvider).valueOrNull == false;

  Future<void> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) async {
    final current = state.valueOrNull ?? const [];
    if (_isOffline) {
      final optimistic = Contact(
        id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        phone: phone,
        relationship: relationship,
        priority: current.length + 1,
        confirmed: false,
        email: email,
      );
      state = AsyncData([...current, optimistic]);
      await ref.read(offlineQueueServiceProvider).enqueue('contacts.add', {
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'email': email,
      });
      return;
    }
    state = AsyncData(
      await ref
          .read(contactsRepositoryProvider)
          .addContact(name, phone, relationship, email: email),
    );
  }

  /// Edits a contact in place — most often to add the email address that
  /// makes an otherwise unreachable contact reachable.
  Future<void> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async {
    final current = state.valueOrNull ?? const [];
    if (_isOffline) {
      state = AsyncData([
        for (final contact in current)
          if (contact.id == id)
            Contact(
              id: contact.id,
              name: name ?? contact.name,
              phone: phone ?? contact.phone,
              relationship: relationship ?? contact.relationship,
              priority: contact.priority,
              confirmed: contact.confirmed,
              email: (email != null && email.isNotEmpty) ? email : contact.email,
            )
          else
            contact,
      ]);
      await ref.read(offlineQueueServiceProvider).enqueue('contacts.update', {
        'id': id,
        'name': name,
        'phone': phone,
        'relationship': relationship,
        'email': email,
      });
      return;
    }
    state = AsyncData(
      await ref.read(contactsRepositoryProvider).updateContact(
            id,
            name: name,
            phone: phone,
            relationship: relationship,
            email: email,
          ),
    );
  }

  /// Emails the contact a code. Returns true when they were already
  /// verified and nothing was sent.
  ///
  /// Not queued when offline: a code the server never issued cannot be
  /// confirmed, so pretending to send one would leave the user waiting for
  /// an email that does not exist.
  Future<bool> sendVerificationCode(String id) {
    return ref.read(contactsRepositoryProvider).sendVerificationCode(id);
  }

  Future<void> confirmVerificationCode(String id, String code) async {
    state = AsyncData(
      await ref.read(contactsRepositoryProvider).confirmVerificationCode(id, code),
    );
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
