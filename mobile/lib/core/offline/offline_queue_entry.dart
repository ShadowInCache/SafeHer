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
    this.ownerId,
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

  /// The account that queued this entry, from the access token's `sub`.
  ///
  /// Entries are replayed with whatever session is current *at drain time*,
  /// which is not necessarily the session that created them: sign out with a
  /// queued contact or alert, sign in as somebody else, and the queue would
  /// happily write one person's data into another person's account. Stamping
  /// the owner lets [OfflineQueueService.drain] hold an entry until its own
  /// account is back, instead of choosing between replaying it wrongly and
  /// dropping an undelivered emergency alert.
  ///
  /// Null on entries written before this field existed, and on entries
  /// queued with no readable token. Those are never replayed — an entry
  /// nobody can be shown to own cannot be safely sent as anybody.
  final String? ownerId;

  OfflineQueueEntry withAttempt() => OfflineQueueEntry(
    id: id,
    actionType: actionType,
    payload: payload,
    createdAt: createdAt,
    sequence: sequence,
    attempts: attempts + 1,
    ownerId: ownerId,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'actionType': actionType,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'sequence': sequence,
    'attempts': attempts,
    'ownerId': ownerId,
  };

  factory OfflineQueueEntry.fromMap(Map<dynamic, dynamic> map) => OfflineQueueEntry(
    id: map['id'] as String,
    actionType: map['actionType'] as String,
    payload: Map<String, dynamic>.from(map['payload'] as Map),
    createdAt: DateTime.parse(map['createdAt'] as String),
    sequence: map['sequence'] as int? ?? 0,
    attempts: map['attempts'] as int? ?? 0,
    ownerId: map['ownerId'] as String?,
  );
}
