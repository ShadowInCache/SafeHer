import 'models/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile> getUserProfile();
}
