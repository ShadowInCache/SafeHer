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
      deviceCount: 3,
      contactsPreview: [
        ProfileContactPreview(id: '1', name: 'Anika Sharma', relationship: 'Sister', priority: 1),
        ProfileContactPreview(id: '2', name: 'Rahul Verma', relationship: 'Partner', priority: 2),
        ProfileContactPreview(id: '3', name: 'Meera Iyer', relationship: 'Friend', priority: 3),
      ],
    );
  }
}
