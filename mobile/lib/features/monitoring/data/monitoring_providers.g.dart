// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monitoring_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$liveMonitoringControllerHash() =>
    r'5212191d20b8e42341aa02c23f24538288e7e594';

/// Drives Live Monitoring off the real `/api/v1/ws/alerts/{user_id}` feed
/// (see `fastapi_app/routers/ws.py`) — no synthetic sensor data, ever.
/// There's nothing flavor-specific to branch on here: without a signed-in
/// backend session (the mock flavor never obtains one — see
/// `AppConfig.useMockApi`) the client simply can't connect and this
/// honestly settles on "disconnected" rather than fabricating a feed.
///
/// Copied from [LiveMonitoringController].
@ProviderFor(LiveMonitoringController)
final liveMonitoringControllerProvider =
    NotifierProvider<LiveMonitoringController, LiveMonitoringState>.internal(
      LiveMonitoringController.new,
      name: r'liveMonitoringControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$liveMonitoringControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$LiveMonitoringController = Notifier<LiveMonitoringState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
