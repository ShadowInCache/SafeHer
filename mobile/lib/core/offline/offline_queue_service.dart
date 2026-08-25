import 'offline_queue_box.dart';
import 'offline_queue_entry.dart';

typedef OfflineActionHandler = Future<void> Function(Map<String, dynamic> payload);

const _maxAttempts = 5;

/// Queues mutations made while offline and replays them once
/// [drain] is called (wired to connectivity regaining a network — see
/// [offlineQueueDrainerProvider]). Feature code that wants offline support
/// for a mutation registers a handler for an action type, enqueues an
/// entry when the mutation can't reach the network, and otherwise doesn't
/// need to know this exists.
class OfflineQueueService {
  OfflineQueueService(this._box, {Future<String?> Function()? currentOwnerId})
      : _currentOwnerId = currentOwnerId ?? (() async => null);

  final OfflineQueueBox _box;

  /// Resolves the account that is signed in *now*. Injected rather than read
  /// from a global so tests can drive two accounts without a real token
  /// store, and so this file never depends on the auth layer.
  final Future<String?> Function() _currentOwnerId;
  final _handlers = <String, OfflineActionHandler>{};

  // DateTime.now() alone isn't collision-resistant enough for id/ordering:
  // platforms with coarser clock resolution can return the same value for
  // two enqueue() calls milliseconds apart, which silently overwrote
  // entries (same id) and made queue order ambiguous (equal createdAt,
  // and List.sort isn't stable). A monotonic counter fixes both.
  var _sequence = 0;

  void registerHandler(String actionType, OfflineActionHandler handler) {
    _handlers[actionType] = handler;
  }

  List<OfflineQueueEntry> get pending => _box.getAll();

  Future<void> enqueue(String actionType, Map<String, dynamic> payload) async {
    final sequence = _sequence++;
    final entry = OfflineQueueEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}-$sequence',
      actionType: actionType,
      payload: payload,
      createdAt: DateTime.now(),
      sequence: sequence,
      // Stamped at enqueue time, while the queueing account is still the
      // signed-in one. Resolving it at drain time would defeat the point.
      ownerId: await _currentOwnerId(),
    );
    return _box.add(entry);
  }

  /// Replays every queued entry in the order it was enqueued. An entry
  /// that fails again is left in the queue (with its attempt count bumped)
  /// unless it's exhausted [_maxAttempts], in which case it's dropped
  /// rather than retried forever.
  /// Replays only the entries belonging to the account that is signed in
  /// now. Anything queued by a different account is left untouched, so it
  /// replays when that account signs back in rather than being sent as
  /// somebody else — and an undelivered emergency alert is neither
  /// misattributed nor thrown away.
  Future<void> drain() async {
    final owner = await _currentOwnerId();
    for (final entry in _box.getAll()) {
      // No signed-in account: nothing can be replayed as anybody.
      if (owner == null) return;
      // Queued by a different account, or by one that cannot be identified.
      // Skipped rather than removed: it is still that account's data, and it
      // is still their alert to deliver.
      if (entry.ownerId != owner) continue;
      final handler = _handlers[entry.actionType];
      if (handler == null) continue;
      try {
        await handler(entry.payload);
        await _box.remove(entry.id);
      } catch (_) {
        if (entry.attempts + 1 >= _maxAttempts) {
          await _box.remove(entry.id);
        } else {
          await _box.update(entry.withAttempt());
        }
      }
    }
  }
}
