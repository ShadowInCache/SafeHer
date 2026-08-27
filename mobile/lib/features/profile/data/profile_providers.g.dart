// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$profileRepositoryHash() => r'cb34aa4db52c713270e508eea328546443b17383';

/// See also [profileRepository].
@ProviderFor(profileRepository)
final profileRepositoryProvider =
    AutoDisposeProvider<ProfileRepository>.internal(
      profileRepository,
      name: r'profileRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$profileRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ProfileRepositoryRef = AutoDisposeProviderRef<ProfileRepository>;
String _$userProfileHash() => r'2e1a85fed371f23ee9c7b733077b21ef25f17b2a';

/// See also [userProfile].
@ProviderFor(userProfile)
final userProfileProvider = AutoDisposeFutureProvider<UserProfile>.internal(
  userProfile,
  name: r'userProfileProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$userProfileHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef UserProfileRef = AutoDisposeFutureProviderRef<UserProfile>;
String _$detectionRepositoryHash() =>
    r'09c481605898b3859ca5a97ea2852c378e57836e';

/// The backend's own account of whether automatic detection is running.
///
/// Kept beside the profile providers because the Profile screen is where the
/// threat-threshold control lives, and a threshold is meaningless without
/// knowing whether anything evaluates it.
///
/// Copied from [detectionRepository].
@ProviderFor(detectionRepository)
final detectionRepositoryProvider =
    AutoDisposeProvider<DetectionRepository>.internal(
      detectionRepository,
      name: r'detectionRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$detectionRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DetectionRepositoryRef = AutoDisposeProviderRef<DetectionRepository>;
String _$detectionStatusHash() => r'5e1bf87b665c92b620bdf710b19bb2f2b537a80d';

/// See also [detectionStatus].
@ProviderFor(detectionStatus)
final detectionStatusProvider =
    AutoDisposeFutureProvider<DetectionStatus>.internal(
      detectionStatus,
      name: r'detectionStatusProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$detectionStatusHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef DetectionStatusRef = AutoDisposeFutureProviderRef<DetectionStatus>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
