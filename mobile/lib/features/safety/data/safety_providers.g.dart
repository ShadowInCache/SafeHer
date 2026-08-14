// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'safety_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$safetyRepositoryHash() => r'514d98d83a4f35242bbfbd44e66f9e8d2f063237';

/// See also [safetyRepository].
@ProviderFor(safetyRepository)
final safetyRepositoryProvider = AutoDisposeProvider<SafetyRepository>.internal(
  safetyRepository,
  name: r'safetyRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$safetyRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SafetyRepositoryRef = AutoDisposeProviderRef<SafetyRepository>;
String _$journeyRepositoryHash() => r'dfdffdc68a139e3627aabbf737bc29b0272ebddf';

/// See also [journeyRepository].
@ProviderFor(journeyRepository)
final journeyRepositoryProvider =
    AutoDisposeProvider<JourneyRepository>.internal(
      journeyRepository,
      name: r'journeyRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$journeyRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef JourneyRepositoryRef = AutoDisposeProviderRef<JourneyRepository>;
String _$journeyHistoryHash() => r'49ea4305e5e476fa4e554fa281e43acd1fa847f3';

/// See also [journeyHistory].
@ProviderFor(journeyHistory)
final journeyHistoryProvider =
    AutoDisposeFutureProvider<List<SafeJourney>>.internal(
      journeyHistory,
      name: r'journeyHistoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$journeyHistoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef JourneyHistoryRef = AutoDisposeFutureProviderRef<List<SafeJourney>>;
String _$safetyPreferencesNotifierHash() =>
    r'997da5d692b4c1e7280ae9ec8906a4219971efb7';

/// The user's opt-in trigger settings. Kept alive because the shake listener
/// and the SOS cancel flow both depend on it outside any one screen.
///
/// Copied from [SafetyPreferencesNotifier].
@ProviderFor(SafetyPreferencesNotifier)
final safetyPreferencesNotifierProvider =
    AsyncNotifierProvider<
      SafetyPreferencesNotifier,
      SafetyPreferences
    >.internal(
      SafetyPreferencesNotifier.new,
      name: r'safetyPreferencesNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$safetyPreferencesNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SafetyPreferencesNotifier = AsyncNotifier<SafetyPreferences>;
String _$safetyPinStatusNotifierHash() =>
    r'811d12dda78b12f5a41152a1c16492b5e68fcdb6';

/// See also [SafetyPinStatusNotifier].
@ProviderFor(SafetyPinStatusNotifier)
final safetyPinStatusNotifierProvider =
    AutoDisposeAsyncNotifierProvider<
      SafetyPinStatusNotifier,
      SafetyPinStatus
    >.internal(
      SafetyPinStatusNotifier.new,
      name: r'safetyPinStatusNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$safetyPinStatusNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$SafetyPinStatusNotifier = AutoDisposeAsyncNotifier<SafetyPinStatus>;
String _$activeJourneyNotifierHash() =>
    r'5d91c167bf8c2d89472e84f2c9723ba3af48a342';

/// The active journey plus the periodic real-GPS breadcrumb loop.
///
/// The loop only runs while a journey is genuinely active and the user has
/// left `journeyAutoShareLocation` on. Every point posted is a real fix from
/// [LocationService] — a failed fix posts nothing rather than repeating the
/// last known position as if it were fresh.
///
/// Copied from [ActiveJourneyNotifier].
@ProviderFor(ActiveJourneyNotifier)
final activeJourneyNotifierProvider =
    AsyncNotifierProvider<ActiveJourneyNotifier, SafeJourney?>.internal(
      ActiveJourneyNotifier.new,
      name: r'activeJourneyNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activeJourneyNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ActiveJourneyNotifier = AsyncNotifier<SafeJourney?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
