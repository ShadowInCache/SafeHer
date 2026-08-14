import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';

class ProfileRepositoryMock implements ProfileRepository {
  UserProfile _profile = const UserProfile(
    name: 'Priya Patel',
    email: 'priya.patel@example.com',
    phone: '+1 (555) 123-4567',
    memberSince: 'March 2025',
    safetyScore: 87,
    streakDays: 12,
  );

  @override
  Future<UserProfile> getUserProfile() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _profile;
  }

  @override
  Future<UserProfile> updateProfile({String? name, String? phone}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _profile = UserProfile(
      name: name ?? _profile.name,
      email: _profile.email,
      phone: phone ?? _profile.phone,
      memberSince: _profile.memberSince,
      safetyScore: _profile.safetyScore,
      streakDays: _profile.streakDays,
    );
    return _profile;
  }
}
