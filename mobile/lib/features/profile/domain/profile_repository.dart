import 'models/user_profile.dart';

abstract class ProfileRepository {
  Future<UserProfile> getUserProfile();

  /// Partial update — pass only the fields that changed. Returns the
  /// updated profile so callers don't need a separate re-fetch.
  ///
  /// [threatThreshold] is SRS FR-EMG-02: the score at which SafeHer raises
  /// the alarm without being asked. It has to reach the server, because
  /// that is where the decision is taken — a value kept only in Hive is a
  /// slider that moves and changes nothing.
  Future<UserProfile> updateProfile({
    String? name,
    String? phone,
    double? threatThreshold,
  });
}
