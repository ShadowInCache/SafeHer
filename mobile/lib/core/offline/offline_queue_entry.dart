/// A single queued mutation, waiting to be replayed once the device is
/// back online. Stored in Hive as a plain map (see [toMap]/[fromMap]) —
/// no generated TypeAdapter needed, since Hive already round-trips
/// Maps/Lists/primitives natively.
class OfflineQueueEntry {
  const OfflineQueueEntry({
    required this.id,
    required this.actionType,
    required this.payload,
    required this.createdAt,
    required this.sequence,
    this.attempts = 0,
  });

  /// Unique per entry (not the id of whatever it's mutating) so the same
  /// contact/report/etc. can be queued for different actions independently.
  final String id;

  /// Identifies which registered handler should replay this entry — e.g.
  /// `'contacts.add'`. See `OfflineQueueService.registerHandler`.
  final String actionType;

  final Map<String, dynamic> payload;
  final DateTime createdAt;

  /// Monotonic enqueue order. Wall-clock time alone can tie on platforms
  /// with coarse clock resolution, and list sorting isn't stable, so
  /// replay order is driven by this instead of [createdAt].
  final int sequence;

  final int attempts;

  OfflineQueueEntry withAttempt() => OfflineQueueEntry(
    id: id,
    actionType: actionType,
    payload: payload,
    createdAt: createdAt,
    sequence: sequence,
    attempts: attempts + 1,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'actionType': actionType,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'sequence': sequence,
    'attempts': attempts,
  };

  factory OfflineQueueEntry.fromMap(Map<dynamic, dynamic> map) => OfflineQueueEntry(
    id: map['id'] as String,
    actionType: map['actionType'] as String,
    payload: Map<String, dynamic>.from(map['payload'] as Map),
    createdAt: DateTime.parse(map['createdAt'] as String),
    sequence: map['sequence'] as int? ?? 0,
    attempts: map['attempts'] as int? ?? 0,
  );
}
