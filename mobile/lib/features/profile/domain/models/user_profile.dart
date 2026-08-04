class ProfileContactPreview {
  const ProfileContactPreview({
    required this.id,
    required this.name,
    required this.relationship,
    required this.priority,
  });

  final String id;
  final String name;
  final String relationship;
  final int priority;
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.memberSince,
    required this.safetyScore,
    required this.streakDays,
    required this.deviceCount,
    required this.contactsPreview,
  });

  final String name;
  final String email;
  final String phone;
  final String memberSince;
  final int safetyScore;
  final int streakDays;
  final int deviceCount;
  final List<ProfileContactPreview> contactsPreview;
}
