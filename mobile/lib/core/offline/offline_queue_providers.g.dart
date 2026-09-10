// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_queue_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$offlineQueueServiceHash() =>
    r'c5948766d17fcf7a2caa61132d772add22c0fbe1';

/// See also [offlineQueueService].
@ProviderFor(offlineQueueService)
final offlineQueueServiceProvider = Provider<OfflineQueueService>.internal(
  offlineQueueService,
  name: r'offlineQueueServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$offlineQueueServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef OfflineQueueServiceRef = ProviderRef<OfflineQueueService>;
String _$offlineQueueDrainerHash() =>
    r'4c7f1e55d972212698ca72ab751efc907864b2a8';

/// Drains the offline queue whenever there is any reason to think it might
/// now succeed.
///
/// **Why this is not just an offline→online listener.** It used to be, and
/// that left queued emergency alerts stranded indefinitely. An alert reaches
/// the queue when a *request* fails, and the most common way for that to
/// happen is a request that timed out while the phone had a perfectly good
/// connection — a sleeping free-tier backend, a slow fan-out, a captive
/// portal. In that case the device never goes offline, so no offline→online
/// transition ever fires, so nothing ever retried. The screen said "will send
/// when you have signal" to someone who had signal the entire time, about an
/// alert that was never going to be sent.
///
/// So there are now three triggers, and they overlap on purpose:
///
/// * **Connectivity returning** — the original one, still the fastest signal
///   when the device genuinely was offline.
/// * **The app coming back to the foreground** — covers the phone that was
///   put away and picked up again, and costs nothing when the queue is empty.
/// * **A periodic sweep** — the backstop that makes the guarantee
///   unconditional. FR-EMG-09 promises the alert is sent on reconnect; a
///   guarantee that depends on a plugin emitting an event is not one.
///
/// Draining an empty queue is a no-op, so the cost of over-triggering is a
/// method call. The cost of under-triggering is an emergency alert nobody
/// ever receives.
///
/// Copied from [OfflineQueueDrainer].
@ProviderFor(OfflineQueueDrainer)
final offlineQueueDrainerProvider =
    NotifierProvider<OfflineQueueDrainer, void>.internal(
      OfflineQueueDrainer.new,
      name: r'offlineQueueDrainerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$offlineQueueDrainerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$OfflineQueueDrainer = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
