import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/offline/offline_queue_service.dart';

import '../../test_utils/offline_test_overrides.dart';

void main() {
  group('OfflineQueueService', () {
    test('enqueue persists an entry with the given action type and payload', () async {
      final box = FakeOfflineQueueBox();
      final service = OfflineQueueService(box);

      await service.enqueue('contacts.add', {'name': 'Test'});

      expect(service.pending, hasLength(1));
      expect(service.pending.first.actionType, 'contacts.add');
      expect(service.pending.first.payload, {'name': 'Test'});
    });

    test('drain replays each entry through its registered handler and removes it on success', () async {
      final box = FakeOfflineQueueBox();
      final service = OfflineQueueService(box);
      final replayed = <Map<String, dynamic>>[];
      service.registerHandler('contacts.add', (payload) async => replayed.add(payload));

      await service.enqueue('contacts.add', {'name': 'A'});
      await service.enqueue('contacts.add', {'name': 'B'});
      await service.drain();

      expect(replayed, [
        {'name': 'A'},
        {'name': 'B'},
      ]);
      expect(service.pending, isEmpty);
    });

    test('drain leaves an entry queued (with attempts bumped) when its handler keeps failing', () async {
      final box = FakeOfflineQueueBox();
      final service = OfflineQueueService(box);
      service.registerHandler('contacts.add', (payload) async => throw Exception('still offline'));

      await service.enqueue('contacts.add', {'name': 'A'});
      await service.drain();

      expect(service.pending, hasLength(1));
      expect(service.pending.first.attempts, 1);
    });

    test('drain drops an entry once it exceeds the retry limit', () async {
      final box = FakeOfflineQueueBox();
      final service = OfflineQueueService(box);
      service.registerHandler('contacts.add', (payload) async => throw Exception('still offline'));

      await service.enqueue('contacts.add', {'name': 'A'});
      for (var i = 0; i < 5; i++) {
        await service.drain();
      }

      expect(service.pending, isEmpty);
    });

    test('drain skips entries with no registered handler, leaving them queued', () async {
      final box = FakeOfflineQueueBox();
      final service = OfflineQueueService(box);

      await service.enqueue('unknown.action', {});
      await service.drain();

      expect(service.pending, hasLength(1));
    });
  });
}
