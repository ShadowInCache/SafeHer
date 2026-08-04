import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';
import 'profile_repository_mock.dart';

part 'profile_providers.g.dart';

@riverpod
ProfileRepository profileRepository(Ref ref) {
  return ProfileRepositoryMock();
}

@riverpod
Future<UserProfile> userProfile(Ref ref) async {
  return ref.watch(profileRepositoryProvider).getUserProfile();
}
