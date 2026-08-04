import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';

class ProfileRepositoryMock implements ProfileRepository {
  @override
  Future<UserProfile> getUserProfile() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return const UserProfile(
      name: 'Priya Patel',
      email: 'priya.patel@example.com',
      phone: '+1 (555) 123-4567',
      memberSince: 'March 2025',
      safetyScore: 87,
      streakDays: 12,
    );
  }
}
