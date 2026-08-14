import 'models/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile> getUserProfile();

  /// Partial update — pass only the fields that changed. Returns the
  /// updated profile so callers don't need a separate re-fetch.
  Future<UserProfile> updateProfile({String? name, String? phone});
}
