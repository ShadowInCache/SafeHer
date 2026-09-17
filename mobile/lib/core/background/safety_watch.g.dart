// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'safety_watch.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$safetyForegroundServiceHash() =>
    r'd253f2348bc70ab20a897b71dbcaa08977010da2';

/// The foreground service for the platform actually being run on.
///
/// Lives here rather than beside the glove, because the service is no longer
/// the glove's: a journey needs it too, and whichever consumer happened to own
/// the provider would look like the only one that mattered.
///
/// Copied from [safetyForegroundService].
@ProviderFor(safetyForegroundService)
final safetyForegroundServiceProvider =
    Provider<SafetyForegroundService>.internal(
      safetyForegroundService,
      name: r'safetyForegroundServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$safetyForegroundServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SafetyForegroundServiceRef = ProviderRef<SafetyForegroundService>;
String _$safetyWatchHash() => r'aca0aab8a7c24dfbf610fc32094ccdfebe20a4c3';

/// Owns the foreground service's lifetime, as the union of everything that
/// currently needs it.
///
/// ## The bug this exists to remove
///
/// The service used to be started by one consumer — a connected glove — and
/// nothing else. A Safe Journey armed with no glove paired therefore ran with
/// no foreground service at all, so Android froze the process the moment the
/// screen went off: the speech recogniser stopped, the camera policy timer
/// stopped, the once-a-second post of the fused score stopped. Meanwhile
/// `threatPipelineArmed` watches only the journey, so the app went on saying
/// it was armed. A woman wearing the glasses and no glove, phone in her
/// pocket, had no audio detection and nothing on screen to tell her.
///
/// ## Why a set of reasons rather than a counter or a flag
///
/// A flag cannot answer "may I stop it now": a journey ending while the glove
/// is still connected would take the glove's BLE stream down with it, which is
/// the same class of failure in the opposite direction. A counter would answer
/// that, but could not say *what* the service is for — and the Android service
/// types and the notification text both have to name the real work. So the
/// reasons are kept, and both are derived from them.
///
/// Claims are idempotent: two callers claiming [WatchReason.glove] is not a
/// thing that happens, but a re-entrant listener firing twice is, and it must
/// not turn into two starts or a release that undercounts.
///
/// Copied from [SafetyWatch].
@ProviderFor(SafetyWatch)
final safetyWatchProvider = NotifierProvider<SafetyWatch, bool>.internal(
  SafetyWatch.new,
  name: r'safetyWatchProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$safetyWatchHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SafetyWatch = Notifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
