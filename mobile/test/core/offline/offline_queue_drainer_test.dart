import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/offline/offline_queue_providers.dart';
import 'package:safeher_app/core/offline/offline_queue_service.dart';

import '../../test_utils/offline_test_overrides.dart';

/// The drainer used to fire on one thing only: a connectivity transition from
/// offline to online.
///
/// That left queued emergency alerts stranded. An alert reaches the queue when
/// a *request* fails, and the most common way for that to happen is a request
/// that timed out while the phone had a perfectly good connection — a
/// sleeping free-tier backend, a slow contact fan-out, a captive portal. The
/// device never went offline, so the transition never happened, so nothing
/// ever retried. The screen promised the alert would send "when you have
/// signal" to someone who had signal the whole time.
///
/// FR-EMG-09 says the alert is sent within thirty seconds of connectivity
/// being restored. A guarantee that depends on a plugin emitting an event is
/// not a guarantee, so there is now also a periodic sweep and an
/// app-resume trigger. These tests pin the sweep, which is the one that makes
/// the promise unconditional.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an alert queued while online still drains, with no transition', (tester) async {
    final queue = OfflineQueueService(FakeOfflineQueueBox());
    var replays = 0;
    queue.registerHandler('emergency.dispatch', (payload) async => replays++);
    await queue.enqueue('emergency.dispatch', {'severity': 'critical'});

    await tester.pumpWidget(
      ProviderScope(
        // Online for the whole test — the connectivity stream never emits a
        // transition, which is exactly the condition that used to strand the
        // alert forever.
        overrides: offlineTestOverrides(offline: false, queueService: queue),
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(offlineQueueDrainerProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    expect(replays, 0, reason: 'nothing should fire before the first sweep');

    // One sweep interval.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(replays, 1, reason: 'the sweep is what makes FR-EMG-09 unconditional');
    expect(queue.pending, isEmpty);
  });

  testWidgets('a drained queue does not replay the same alert twice', (tester) async {
    // Over-triggering is safe by design — three triggers overlap on purpose —
    // but only because a drained entry is removed. Replaying an emergency
    // would message every contact again.
    final queue = OfflineQueueService(FakeOfflineQueueBox());
    var replays = 0;
    queue.registerHandler('emergency.dispatch', (payload) async => replays++);
    await queue.enqueue('emergency.dispatch', {'severity': 'critical'});

    await tester.pumpWidget(
      ProviderScope(
        overrides: offlineTestOverrides(offline: false, queueService: queue),
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(offlineQueueDrainerProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    expect(replays, 1);
  });
}
