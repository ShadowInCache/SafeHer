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
  // Kept alive across navigation. This is auto-dispose by default, so the
  // profile was thrown away the moment Home was left and re-fetched on
  // arriving at Profile -- which meant a full shimmer on every single visit,
  // against a backend that sleeps and cold-starts. Home had already loaded
  // the name; there was no reason to ask again.
  //
  // Safe to hold: the two places that need it fresh both invalidate it
  // explicitly -- the Profile screen after an edit or retry, and
  // session_reset on sign-out, so one account's profile can never survive
  // into another's session.
  ref.keepAlive();
  return ref.watch(profileRepositoryProvider).getUserProfile();
}

/// The backend's own account of whether automatic detection is running.
///
/// Kept beside the profile providers because the Profile screen is where the
/// threat-threshold control lives, and a threshold is meaningless without
/// knowing whether anything evaluates it.
@riverpod
DetectionRepository detectionRepository(Ref ref) {
  // Every other repository provider branches on useMockApi; this one did not,
  // so the flavour documented as "explore the UI on fixture data without
  // running the backend at all" still called the live API for detection
  // status. On web that surfaced as a CORS failure against the deployed
  // backend; on a device it meant the Profile screen's detection line waited
  // on a server the mock flavour exists to avoid.
  //
  // DetectionRepositoryFake's own doc comment already claimed it was "used by
  // widget tests and the mock flavour" -- only the first half was true.
  //
  // The fixture reports no trained models, which is what an unconfigured
  // deployment actually returns. Reporting the pipeline as live here would
  // make the threshold slider look like it governs something it does not,
  // and that is the one thing this screen is careful not to do.
  if (AppConfig.useMockApi) {
    return DetectionRepositoryFake(
      const DetectionStatus(
        pipelineLive: false,
        anyModelReady: false,
        scoresAreCallerSupplied: true,
      ),
    );
  }
  return DetectionRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
Future<DetectionStatus> detectionStatus(Ref ref) =>
    ref.watch(detectionRepositoryProvider).fetchStatus();
