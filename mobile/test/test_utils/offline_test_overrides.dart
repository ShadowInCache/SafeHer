import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/core/connectivity/connectivity_notifier.dart';
import 'package:safeher_app/core/offline/offline_queue_box.dart';
import 'package:safeher_app/core/offline/offline_queue_entry.dart';
import 'package:safeher_app/core/offline/offline_queue_providers.dart';
import 'package:safeher_app/core/offline/offline_queue_service.dart';

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
List<Override> offlineTestOverrides({bool offline = false, OfflineQueueService? queueService}) => [
  connectivityNotifierProvider.overrideWith(
    offline ? _AlwaysOfflineConnectivityNotifier.new : _AlwaysOnlineConnectivityNotifier.new,
  ),
  offlineQueueServiceProvider.overrideWithValue(queueService ?? OfflineQueueService(FakeOfflineQueueBox())),
];
