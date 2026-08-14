class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.memberSince,
    required this.safetyScore,
    required this.streakDays,
  });

  final String name;
  final String email;
  final String phone;
  final String memberSince;

  /// Null when the backend has no safety-score/streak concept for this
  /// user yet (it doesn't exist as a backend feature today) — shown as
  /// "—" rather than a fabricated number.
  final int? safetyScore;
  final int? streakDays;
}
