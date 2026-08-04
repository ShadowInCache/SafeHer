/// A single emergency contact. This is the canonical shape shared by every
/// feature that reads or manages contacts (Settings, Emergency, Search,
/// Profile) — there is exactly one contacts list in the app, not a
/// per-feature copy of it.
class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.priority,
    required this.confirmed,
  });

  final String id;
  final String name;
  final String relationship;
  final int priority;
  final bool confirmed;
}
