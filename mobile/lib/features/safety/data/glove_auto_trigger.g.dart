// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glove_auto_trigger.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

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
String _$gloveWatchServiceHash() => r'9e44bea55e8a4a1173dc00cb6f3d1a4f81bb109d';

/// Claims the background watch for exactly as long as a glove is being
/// listened to.
///
/// Tied to the glove rather than to a switch of its own, because there is
/// nothing here for the service to keep alive when no glove is connected. A
/// persistent "watching your glove" notification sitting over no glove would
/// be the same lie this file exists to remove, in the opposite direction.
///
/// **It no longer starts and stops the service directly.** [SafetyWatch] owns
/// that, because the glove is not the only thing that needs the process kept
/// alive — an armed journey needs it for the microphone — and two owners
/// calling `start` and `stop` on one operating-system object means whichever
/// finished first switched the other one off.
///
/// The published value is whether the background watch is genuinely running,
/// which is what the Profile screen turns into "you can put your phone in
/// your pocket". It is asked of the platform rather than remembered, so a
/// service the system quietly stopped is not reported as active.
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
