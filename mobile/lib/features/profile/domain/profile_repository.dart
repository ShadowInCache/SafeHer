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

  /// Everything the server holds about this account, as JSON bytes.
  ///
  /// GDPR Article 15, the counterpart to the erasure already offered beside
  /// it. The Profile screen shipped a "Download My Data" button for months
  /// that opened a sheet admitting no export endpoint existed — a truthful
  /// placeholder, and not the feature the button named.
  ///
  /// Returns the encoded document rather than a parsed map: the caller's job
  /// is to hand it to the user, not to read it, and re-encoding a decoded map
  /// would quietly reorder and reformat what the server produced.
  Future<List<int>> exportMyData();
}
