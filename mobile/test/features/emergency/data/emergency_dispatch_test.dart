import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/core/connectivity/connectivity_notifier.dart';
import 'package:safeher_app/features/emergency/data/emergency_providers.dart';
import 'package:safeher_app/features/emergency/domain/emergency_repository.dart';

import '../../../test_utils/offline_test_overrides.dart';

/// An SOS is always attempted. It is never filed away unattempted on the word
/// of a connectivity plugin.
///
/// The dispatcher used to check `connectivity_plus` first and, if it said
/// offline, queue without trying. But that plugin reports whether a network
/// *interface* is up, which is not the question — a captive portal, a VPN, or
/// a device it simply misreads all produce a false negative. It also returned
/// an empty list in some conditions, which the old code read as "offline".
///
/// The result on a real phone: the SOS went into a queue while the connection
/// was working, and the screen told the woman holding it that her contacts
/// would be alerted "when you have signal".
class _RecordingRepository implements EmergencyRepository {
  _RecordingRepository({this.fails = false});

  final bool fails;
  int attempts = 0;

  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    attempts++;
    if (fails) throw Exception('network down');
    return const DispatchOutcome(
      incidentId: 'inc-1',
      contactsTotal: 2,
      contactsNotified: 2,
      reachedContactIds: ['c1', 'c2'],
    );
  }
}

ProviderContainer _container(_RecordingRepository repository, {required bool offline}) {
  final container = ProviderContainer(
    overrides: [
      emergencyRepositoryProvider.overrideWithValue(repository),
      ...offlineTestOverrides(offline: offline),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Dispatches, having first let the connectivity provider actually emit.
///
/// This await is the whole test. `valueOrNull` is null while a stream
/// provider is still loading, so a dispatch fired immediately never sees
/// "offline" at all — an earlier version of this file passed happily against
/// the buggy code for exactly that reason, which made it worse than no test.
Future<DispatchResult> _dispatch(ProviderContainer container) async {
  await container.read(connectivityNotifierProvider.future);
  return container.read(emergencyDispatchNotifierProvider.notifier).dispatch(
    severity: 'critical',
    summary: 'Emergency SOS triggered',
    auto: false,
    latitude: 12.85,
    longitude: 77.68,
  );
}

void main() {
  test('a working connection sends, and reports who was reached', () async {
    final repository = _RecordingRepository();

    final result = await _dispatch(_container(repository, offline: false));

    expect(repository.attempts, 1);
    expect(result.isQueued, isFalse);
    expect(result.outcome.contactsNotified, 2);
  });

  test('the alert is attempted even when connectivity reports offline', () async {
    // The regression that matters. The plugin says offline; the network is
    // fine; the alert must still go.
    final repository = _RecordingRepository();

    final result = await _dispatch(_container(repository, offline: true));

    expect(repository.attempts, 1, reason: 'an SOS is never queued unattempted');
    expect(result.isQueued, isFalse, reason: 'the send succeeded, so nothing to queue');
  });

  test('a failed attempt is queued rather than lost', () async {
    // The queue still exists and still matters — it is reached because
    // sending genuinely did not work, not because a plugin predicted it.
    final repository = _RecordingRepository(fails: true);

    final result = await _dispatch(_container(repository, offline: false));

    expect(repository.attempts, 1);
    expect(result.isQueued, isTrue);
  });

  test('a failure while reported offline is attempted once, then queued', () async {
    final repository = _RecordingRepository(fails: true);

    final result = await _dispatch(_container(repository, offline: true));

    expect(repository.attempts, 1, reason: 'still tried');
    expect(result.isQueued, isTrue, reason: 'and queued only after it failed');
  });
}
