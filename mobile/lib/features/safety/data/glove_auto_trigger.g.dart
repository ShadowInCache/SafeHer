// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glove_auto_trigger.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$safetyForegroundServiceHash() =>
    r'd253f2348bc70ab20a897b71dbcaa08977010da2';

/// The platform's foreground service, or a no-op where there isn't one.
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
String _$gloveAutoTriggerHash() => r'b74f88bdf05956c751d0a7cb919fc1e0ed5c9d5f';

/// Votes on the glove's classifications and publishes the decision to alarm.
///
/// **Why this is a provider and not a widget.**  This vote used to live in the
/// `build()` method of `SafetyTriggerListener`. That worked on screen and
/// nowhere else: Flutter stops pumping frames when the app is not visible, so
/// `build()` stopped being called, the classifications went nowhere, and a
/// pocketed phone — the case the glove exists for — raised nothing. A
/// foreground service alone would not have fixed it; the process would have
/// been alive with nothing reading the stream.
///
/// A `ref.listen` callback is driven by provider state, not by the frame
/// pipeline, so it runs whether or not anything is being drawn.
///
/// It publishes a request rather than dispatching, or even navigating:
/// deciding to alarm and deciding how to show the countdown are different
/// jobs, and only the second one needs a `BuildContext`.
///
/// Copied from [GloveAutoTrigger].
@ProviderFor(GloveAutoTrigger)
final gloveAutoTriggerProvider =
    NotifierProvider<GloveAutoTrigger, GloveAlarmRequest?>.internal(
      GloveAutoTrigger.new,
      name: r'gloveAutoTriggerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$gloveAutoTriggerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GloveAutoTrigger = Notifier<GloveAlarmRequest?>;
String _$gloveWatchServiceHash() => r'bd305bb55554d7ecf7c9438684227cc5269ae4a5';

/// Runs the foreground service for exactly as long as a glove is being
/// listened to.
///
/// Tied to the glove rather than to a switch of its own, because the service
/// has one job — keep the BLE stream and the vote alive — and there is nothing
/// for it to keep alive when no glove is connected. A persistent "SafeHer is
/// watching your glove" notification sitting over no glove would be the same
/// lie this file exists to remove, in the opposite direction.
///
/// Whether it is actually running is asked of the platform and published here,
/// so the UI can distinguish "the glove is connected" from "the glove will
/// still be watching when the screen goes off". They are not the same promise.
///
/// Copied from [GloveWatchService].
@ProviderFor(GloveWatchService)
final gloveWatchServiceProvider =
    NotifierProvider<GloveWatchService, bool>.internal(
      GloveWatchService.new,
      name: r'gloveWatchServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$gloveWatchServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$GloveWatchService = Notifier<bool>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
