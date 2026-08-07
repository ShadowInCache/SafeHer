import 'package:hive_flutter/hive_flutter.dart';

import 'offline_queue_entry.dart';

const offlineQueueBoxName = 'safeher_offline_queue';

/// Thin, testable wrapper around the Hive box that persists
/// [OfflineQueueEntry] records across app restarts — a queued action
/// survives the app being killed while offline, not just backgrounded.
class OfflineQueueBox {
  OfflineQueueBox(this._box);

  final Box<Map> _box;

  List<OfflineQueueEntry> getAll() {
    return _box.values.map(OfflineQueueEntry.fromMap).toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  }

  Future<void> add(OfflineQueueEntry entry) => _box.put(entry.id, entry.toMap());

  Future<void> update(OfflineQueueEntry entry) => _box.put(entry.id, entry.toMap());

  Future<void> remove(String id) => _box.delete(id);

  Future<void> clear() => _box.clear();
}
