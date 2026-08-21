// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emergency_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$emergencyRepositoryHash() =>
    r'2851f3b65166e54e5302a6fc6ed40058bb9db194';

/// See also [emergencyRepository].
@ProviderFor(emergencyRepository)
final emergencyRepositoryProvider =
    AutoDisposeProvider<EmergencyRepository>.internal(
      emergencyRepository,
      name: r'emergencyRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$emergencyRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EmergencyRepositoryRef = AutoDisposeProviderRef<EmergencyRepository>;
String _$evidenceRepositoryHash() =>
    r'a5269010105b3cd4d0b8bd492c817199e471eec7';

/// See also [evidenceRepository].
@ProviderFor(evidenceRepository)
final evidenceRepositoryProvider =
    AutoDisposeProvider<EvidenceRepository>.internal(
      evidenceRepository,
      name: r'evidenceRepositoryProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$evidenceRepositoryHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EvidenceRepositoryRef = AutoDisposeProviderRef<EvidenceRepository>;
String _$evidenceRecorderHash() => r'4de784eda0062e43f4ba2403bfa03d37492306a1';

/// One recorder for the app: it owns a platform resource (the microphone)
/// that must not be opened twice.
///
/// Copied from [evidenceRecorder].
@ProviderFor(evidenceRecorder)
final evidenceRecorderProvider = Provider<EvidenceRecorder>.internal(
  evidenceRecorder,
  name: r'evidenceRecorderProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$evidenceRecorderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EvidenceRecorderRef = ProviderRef<EvidenceRecorder>;
String _$videoRecorderHash() => r'b35176791f38b19ce88025553ccc109adc6223fc';

/// The camera, on the same terms as the microphone above.
///
/// Separate from [evidenceRecorder] on purpose: video is captured in
/// addition to audio and never instead of it, so a camera that cannot open
/// must not be able to take the audio recorder down with it.
///
/// Copied from [videoRecorder].
@ProviderFor(videoRecorder)
final videoRecorderProvider = Provider<VideoEvidenceRecorder>.internal(
  videoRecorder,
  name: r'videoRecorderProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$videoRecorderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef VideoRecorderRef = ProviderRef<VideoEvidenceRecorder>;
String _$emergencyDispatchNotifierHash() =>
    r'685e1d5e0d79fabaf3754646bb56832960a32871';

/// Dispatches the SOS alert. If the device is offline when the countdown
/// completes, the alert is queued via [OfflineQueueService] instead of
/// being dropped, and replays automatically the next time connectivity is
/// restored — satisfying "Offline SOS: disable network → trigger →
/// re-enable → alert sent" without blocking the on-screen dispatched
/// confirmation, which still shows immediately either way (the user
/// shouldn't have to wonder whether their SOS "worked" just because
/// they're in a signal dead zone).
///
/// Copied from [EmergencyDispatchNotifier].
@ProviderFor(EmergencyDispatchNotifier)
final emergencyDispatchNotifierProvider =
    NotifierProvider<EmergencyDispatchNotifier, void>.internal(
      EmergencyDispatchNotifier.new,
      name: r'emergencyDispatchNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$emergencyDispatchNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$EmergencyDispatchNotifier = Notifier<void>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
