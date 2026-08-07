import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../connectivity/connectivity_notifier.dart';
import '../di/injection.dart';
import 'offline_queue_box.dart';
import 'offline_queue_service.dart';

part 'offline_queue_providers.g.dart';

@Riverpod(keepAlive: true)
OfflineQueueService offlineQueueService(Ref ref) {
  return OfflineQueueService(getIt<OfflineQueueBox>());
}

/// Watches connectivity and drains the offline queue on every
/// offline→online transition. Read this provider once near the app root
/// (see `SafeHerApp`) purely to keep it alive — it has no UI of its own.
@Riverpod(keepAlive: true)
class OfflineQueueDrainer extends _$OfflineQueueDrainer {
  bool? _wasOnline;

  @override
  void build() {
    ref.listen(connectivityNotifierProvider, (previous, next) {
      final isOnline = next.valueOrNull;
      if (isOnline == true && _wasOnline == false) {
        ref.read(offlineQueueServiceProvider).drain();
      }
      if (isOnline != null) _wasOnline = isOnline;
    });
  }
}
