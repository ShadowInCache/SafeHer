// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'threat_pipeline.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$threatPhraseClassifierHash() =>
    r'a8baf095ba16bb5584dd163653179d09eab09277';

/// The phrase classifier, loaded once from assets.
///
/// Copied from [threatPhraseClassifier].
@ProviderFor(threatPhraseClassifier)
final threatPhraseClassifierProvider =
    FutureProvider<ThreatPhraseClassifier>.internal(
      threatPhraseClassifier,
      name: r'threatPhraseClassifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$threatPhraseClassifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ThreatPhraseClassifierRef = FutureProviderRef<ThreatPhraseClassifier>;
String _$threatSignalAggregatorHash() =>
    r'fd3509d768733e96bc1f52d3bb6d17b649afe4d7';

/// See also [threatSignalAggregator].
@ProviderFor(threatSignalAggregator)
final threatSignalAggregatorProvider =
    Provider<ThreatSignalAggregator>.internal(
      threatSignalAggregator,
      name: r'threatSignalAggregatorProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$threatSignalAggregatorHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ThreatSignalAggregatorRef = ProviderRef<ThreatSignalAggregator>;
String _$threatPipelineArmedHash() =>
    r'42672e6638fe34a44f12447f2fffa902fd24b09b';

/// Whether continuous detection is allowed to run right now.
///
/// Tied to a journey rather than to a switch of its own. The microphone and
/// the camera are the two most intrusive things this app can touch, and
/// "while she told us she is travelling" is a boundary she set herself — a
/// standing permission to listen would be a different product.
///
/// Copied from [threatPipelineArmed].
@ProviderFor(threatPipelineArmed)
final threatPipelineArmedProvider = Provider<bool>.internal(
  threatPipelineArmed,
  name: r'threatPipelineArmedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$threatPipelineArmedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ThreatPipelineArmedRef = ProviderRef<bool>;
String _$journeyDetectionStatusHash() =>
    r'd16b20eea81cab886f6af6c867763f95efbb1906';

/// What the pipeline is currently doing, readable without starting it.
///
/// **Why this exists separately from [ThreatPipeline].** The Profile screen
/// shows a line describing what can raise an alarm right now, and reading the
/// pipeline directly to find out made rendering that line *construct* the
/// pipeline — which opens the microphone. A settings screen must not be able
/// to start listening by being drawn.
///
/// So the pipeline writes here and the UI reads here. This provider has no
/// dependencies, defaults to "nothing is running", and can be watched by
/// anything at any time without side effects.
///
/// Copied from [JourneyDetectionStatus].
@ProviderFor(JourneyDetectionStatus)
final journeyDetectionStatusProvider =
    NotifierProvider<JourneyDetectionStatus, ThreatPipelineStatus>.internal(
      JourneyDetectionStatus.new,
      name: r'journeyDetectionStatusProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$journeyDetectionStatusHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$JourneyDetectionStatus = Notifier<ThreatPipelineStatus>;
String _$threatPipelineHash() => r'5a506efdd0bf73b337a4cdfee064c6fd55709320';

/// Starts and stops the three signals together, and feeds their scores out.
///
/// ## Why this is a provider and not a widget
///
/// The same reason `GloveAutoTrigger` is. Detection has to keep running with
/// the screen off — a phone in a pocket is the case the whole feature exists
/// for — and `build()` stops being called the moment Flutter stops pumping
/// frames. Everything here hangs off `ref.listen`, which is driven by provider
/// state rather than by the frame pipeline.
///
/// ## What it does not do
///
/// It does not decide anything. Each signal is reported to the aggregator,
/// which sends all three to the server, where `threat_fusion` weighs them
/// together and applies the threshold, the hysteresis and the dedup. No single
/// signal here can raise an alarm on its own, and that is the design: a
/// frightened sentence, a knife-shaped reflection and a dropped bag are each
/// wrong often enough that acting on one alone would train users to ignore it.
///
/// Copied from [ThreatPipeline].
@ProviderFor(ThreatPipeline)
final threatPipelineProvider =
    NotifierProvider<ThreatPipeline, ThreatPipelineStatus>.internal(
      ThreatPipeline.new,
      name: r'threatPipelineProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$threatPipelineHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$ThreatPipeline = Notifier<ThreatPipelineStatus>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
