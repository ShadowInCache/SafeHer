/// A single emergency contact. This is the canonical shape shared by every
/// feature that reads or manages contacts (Settings, Emergency, Search,
/// Profile) — there is exactly one contacts list in the app, not a
/// per-feature copy of it.
class Contact {
  const Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relationship,
    required this.priority,
    required this.confirmed,
    this.email,
  });

  final String id;
  final String name;
  final String phone;
  final String relationship;
  final int priority;
  final bool confirmed;

  /// Optional, but the only emergency channel this project can afford to
  /// run: OneSignal's free tier covers 10,000 emails a month, while SMS
  /// costs money with every provider. A contact with an email address can
  /// be reached even when no SMS credit exists.
  final String? email;

  bool get hasEmail => (email ?? '').isNotEmpty;
}
