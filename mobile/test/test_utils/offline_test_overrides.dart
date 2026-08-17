import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/core/connectivity/connectivity_notifier.dart';
import 'package:safeher_app/core/detection/detection_repository.dart';
import 'package:safeher_app/core/detection/detection_status.dart';
import 'package:safeher_app/core/offline/offline_queue_box.dart';
import 'package:safeher_app/core/offline/offline_queue_entry.dart';
import 'package:safeher_app/core/offline/offline_queue_providers.dart';
import 'package:safeher_app/core/network/backend_warmer.dart';
import 'package:safeher_app/core/network/network_providers.dart';
import 'package:safeher_app/core/offline/offline_queue_service.dart';
import 'package:safeher_app/features/profile/data/profile_providers.dart';

/// In-memory stand-in for the Hive-backed box — avoids needing
/// `Hive.initFlutter()` (never called in widget tests) just to construct
/// an [OfflineQueueService].
class FakeOfflineQueueBox implements OfflineQueueBox {
  final _entries = <String, OfflineQueueEntry>{};

  @override
  List<OfflineQueueEntry> getAll() => _entries.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> add(OfflineQueueEntry entry) async => _entries[entry.id] = entry;

  @override
  Future<void> update(OfflineQueueEntry entry) async => _entries[entry.id] = entry;

  @override
  Future<void> remove(String id) async => _entries.remove(id);

  @override
  Future<void> clear() async => _entries.clear();
}

class _AlwaysOnlineConnectivityNotifier extends ConnectivityNotifier {
  @override
  Stream<bool> build() => Stream.value(true);
}

class _AlwaysOfflineConnectivityNotifier extends ConnectivityNotifier {
  @override
  Stream<bool> build() => Stream.value(false);
}

/// Every screen that reads `contactsNotifierProvider` (directly or via
/// `ContactsNotifier`) transitively needs connectivity + the offline queue
/// service — spread this into any test harness's `ProviderScope.overrides`
/// alongside the screen's own repository overrides.
List<Override> offlineTestOverrides({
  bool offline = false,
  OfflineQueueService? queueService,
  DetectionStatus? detectionStatus,
}) => [
  connectivityNotifierProvider.overrideWith(
    offline ? _AlwaysOfflineConnectivityNotifier.new : _AlwaysOnlineConnectivityNotifier.new,
  ),
  offlineQueueServiceProvider.overrideWithValue(queueService ?? OfflineQueueService(FakeOfflineQueueBox())),
  // The Profile screen asks the backend whether automatic detection is
  // running. Left un-overridden that is a real HTTP call, whose timeout timer
  // outlives the widget tree and fails the test with "A Timer is still
  // pending" -- a failure that names the symptom and not the network call
  // behind it. Defaults to the honest production state: not detecting.
  // Same reason as the detection repository below: a real warm-up call
  // leaves a timeout timer outliving the widget tree.
  backendWarmerProvider.overrideWithValue(const BackendWarmerNoop()),
  detectionRepositoryProvider.overrideWithValue(
    DetectionRepositoryFake(detectionStatus ?? DetectionStatus.unknown),
  ),
];
