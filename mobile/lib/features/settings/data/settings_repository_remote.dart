import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/app_settings.dart';
import '../domain/settings_repository.dart';

/// Firestore-backed [SettingsRepository]. Preferences live in a single doc
/// at `users/{uid}/settings/preferences` — there's only ever one, so no
/// list/collection semantics are needed.
class SettingsRepositoryRemote implements SettingsRepository {
  SettingsRepositoryRemote({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _doc {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return _firestore.collection('users').doc(uid).collection('settings').doc('preferences');
  }

  static const _defaults = AppSettings(pushNotifications: true, locationSharing: true, biometricLock: false);

  @override
  Future<AppSettings> getSettings() async {
    final snapshot = await _doc.get();
    final data = snapshot.data();
    if (data == null) return _defaults;
    return AppSettings(
      pushNotifications: data['pushNotifications'] as bool? ?? _defaults.pushNotifications,
      locationSharing: data['locationSharing'] as bool? ?? _defaults.locationSharing,
      biometricLock: data['biometricLock'] as bool? ?? _defaults.biometricLock,
    );
  }

  @override
  Future<AppSettings> updateSettings(AppSettings settings) async {
    await _doc.set({
      'pushNotifications': settings.pushNotifications,
      'locationSharing': settings.locationSharing,
      'biometricLock': settings.biometricLock,
    }, SetOptions(merge: true));
    return settings;
  }
}
