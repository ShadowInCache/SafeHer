import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/offline/offline_queue_box.dart';
import 'package:safeher_app/core/offline/offline_queue_entry.dart';
import 'package:safeher_app/core/offline/offline_queue_service.dart';
import 'package:safeher_app/core/offline/queue_owner.dart';

/// Cross-account isolation for the offline queue.
///
/// The queue is `keepAlive` and Hive-backed, so it outlives a sign-out. It
/// replayed whatever it held under whichever account was signed in when the
/// drain happened, and entries carried no owner — so Account A could go
/// offline, add an emergency contact, sign out, and have that contact written
/// into Account B's account the moment B came online. `emergency.dispatch`
/// rode the same path, which means one person's SOS could have been sent as
/// another person's.
///
/// These tests drive two accounts against one queue, which is the only
/// arrangement that can catch it: every single-user test passed throughout.
class _MemoryQueueBox implements OfflineQueueBox {
  final _entries = <String, OfflineQueueEntry>{};

  @override
  Future<void> add(OfflineQueueEntry entry) async => _entries[entry.id] = entry;

  @override
  List<OfflineQueueEntry> getAll() {
    final all = _entries.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
    return all;
  }

  @override
  Future<void> remove(String id) async => _entries.remove(id);

  @override
  Future<void> update(OfflineQueueEntry entry) async => _entries[entry.id] = entry;

  @override
  Future<void> clear() async => _entries.clear();
}

void main() {
  group('offline queue owner scoping', () {
    late _MemoryQueueBox box;
    late String? signedIn;
    late OfflineQueueService queue;
    late List<Map<String, dynamic>> replayed;

    setUp(() {
      box = _MemoryQueueBox();
      signedIn = 'account-a';
      replayed = [];
      queue = OfflineQueueService(box, currentOwnerId: () async => signedIn);
      queue.registerHandler('contacts.add', (payload) async => replayed.add(payload));
      queue.registerHandler('emergency.dispatch', (payload) async => replayed.add(payload));
    });

    test("account B's drain does not replay account A's queued contact", () async {
      await queue.enqueue('contacts.add', {'name': 'Anika', 'phone': '+15550101001'});

      // A signs out; B signs in on the same device.
      signedIn = 'account-b';
      await queue.drain();

      expect(
        replayed,
        isEmpty,
        reason: "account A's contact must not be written into account B's account",
      );
      expect(
        box.getAll().length,
        1,
        reason: 'it is still A\'s data and A\'s to deliver, so it is kept, not dropped',
      );
    });

    test("account A's queued alert is still delivered when A signs back in", () async {
      await queue.enqueue('emergency.dispatch', {'incidentId': 'abc'});

      signedIn = 'account-b';
      await queue.drain();
      expect(replayed, isEmpty);

      // The whole point of holding rather than dropping: A's undelivered
      // emergency alert survives someone else using the phone in between.
      signedIn = 'account-a';
      await queue.drain();

      expect(replayed, [
        {'incidentId': 'abc'},
      ]);
      expect(box.getAll(), isEmpty, reason: 'delivered entries are removed');
    });

    test('nothing is replayed while no account is signed in', () async {
      await queue.enqueue('contacts.add', {'name': 'Anika'});

      signedIn = null;
      await queue.drain();

      expect(replayed, isEmpty);
      expect(box.getAll().length, 1);
    });

    test('entries queued before owners existed are never replayed', () async {
      // Written by an older build: no ownerId, so it cannot be shown to
      // belong to anyone, so it cannot safely be sent as anyone.
      await box.add(
        OfflineQueueEntry(
          id: 'legacy-1',
          actionType: 'contacts.add',
          payload: const {'name': 'Legacy'},
          createdAt: DateTime(2026),
          sequence: 0,
        ),
      );

      await queue.drain();

      expect(replayed, isEmpty);
    });

    test('the owning account still drains its own entries normally', () async {
      await queue.enqueue('contacts.add', {'name': 'Anika'});
      await queue.drain();

      expect(replayed.single['name'], 'Anika');
      expect(box.getAll(), isEmpty);
    });

    test('mixed queues replay only the signed-in account\'s entries', () async {
      await queue.enqueue('contacts.add', {'name': 'A-contact'});
      signedIn = 'account-b';
      await queue.enqueue('contacts.add', {'name': 'B-contact'});

      await queue.drain();

      expect(replayed.map((e) => e['name']), ['B-contact']);
      expect(box.getAll().single.payload['name'], 'A-contact');
    });
  });

  group('accountIdFromAccessToken', () {
    String jwt(String payloadJson) {
      String seg(String raw) =>
          base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
      return '${seg('{"alg":"HS256"}')}.${seg(payloadJson)}.signature';
    }

    test('reads the sub claim', () {
      expect(accountIdFromAccessToken(jwt('{"sub":"user-123"}')), 'user-123');
    });

    test('two accounts produce different ids', () {
      expect(
        accountIdFromAccessToken(jwt('{"sub":"user-a"}')),
        isNot(accountIdFromAccessToken(jwt('{"sub":"user-b"}'))),
      );
    });

    test('unreadable tokens are owner-unknown, not a match', () {
      expect(accountIdFromAccessToken(null), isNull);
      expect(accountIdFromAccessToken(''), isNull);
      expect(accountIdFromAccessToken('not-a-jwt'), isNull);
      expect(accountIdFromAccessToken('a.b'), isNull);
      expect(accountIdFromAccessToken(jwt('{"no_sub":true}')), isNull);
    });
  });
}
