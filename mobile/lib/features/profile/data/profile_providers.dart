import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/network_providers.dart';
import '../domain/models/user_profile.dart';
import '../domain/profile_repository.dart';
import 'profile_repository_mock.dart';
import 'profile_repository_remote.dart';

part 'profile_providers.g.dart';

@riverpod
ProfileRepository profileRepository(Ref ref) {
  if (AppConfig.useMockApi) return ProfileRepositoryMock();
  return ProfileRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
Future<UserProfile> userProfile(Ref ref) async {
  return ref.watch(profileRepositoryProvider).getUserProfile();
}
