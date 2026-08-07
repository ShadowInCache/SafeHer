import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';

/// Combines Firebase Auth (name, email — the identity fields FirebaseAuth
/// already owns) with a Firestore doc at `users/{uid}` for the rest
/// (phone, membership date, safety score, streak). Auth is the source of
/// truth for identity; Firestore is the source of truth for app-specific
/// profile data.
class ProfileRepositoryRemote implements ProfileRepository {
  ProfileRepositoryRemote({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  @override
  Future<UserProfile> getUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No signed-in user.');

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data() ?? const <String, dynamic>{};

    final memberSinceTimestamp = data['memberSince'] as Timestamp?;
    final memberSince = memberSinceTimestamp != null
        ? DateFormat('MMMM yyyy').format(memberSinceTimestamp.toDate())
        : (user.metadata.creationTime != null ? DateFormat('MMMM yyyy').format(user.metadata.creationTime!) : '—');

    return UserProfile(
      name: user.displayName ?? data['name'] as String? ?? 'SafeHer User',
      email: user.email ?? data['email'] as String? ?? '',
      phone: user.phoneNumber ?? data['phone'] as String? ?? '',
      memberSince: memberSince,
      safetyScore: (data['safetyScore'] as num?)?.toInt() ?? 0,
      streakDays: (data['streakDays'] as num?)?.toInt() ?? 0,
    );
  }
}
