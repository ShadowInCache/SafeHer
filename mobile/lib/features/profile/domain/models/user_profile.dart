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
  final int safetyScore;
  final int streakDays;
}
