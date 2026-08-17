import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/detection/detection_repository.dart';
import '../../../core/detection/detection_status.dart';
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

/// The backend's own account of whether automatic detection is running.
///
/// Kept beside the profile providers because the Profile screen is where the
/// threat-threshold control lives, and a threshold is meaningless without
/// knowing whether anything evaluates it.
@riverpod
DetectionRepository detectionRepository(Ref ref) =>
    DetectionRepositoryRemote(apiClient: ref.watch(apiClientProvider));

@riverpod
Future<DetectionStatus> detectionStatus(Ref ref) =>
    ref.watch(detectionRepositoryProvider).fetchStatus();
