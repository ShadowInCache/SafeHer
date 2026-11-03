import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safeher_app/core/network/api_client.dart';
import 'package:safeher_app/features/emergency/data/emergency_providers.dart';
import 'package:safeher_app/features/emergency/domain/emergency_repository.dart';
import 'package:safeher_app/features/safety/data/auto_sos_retraction.dart';
import 'package:safeher_app/features/safety/data/threat_signal_aggregator.dart';

/// Serves a fixed `/alerts/analyze` body so the aggregator's reading of the
/// verdict can be tested without a backend.
class _VerdictApiClient implements ApiClient {
  _VerdictApiClient(this.body);

  final Map<String, dynamic> body;
  int posts = 0;

  @override
  late final Dio dio = Dio()
    ..httpClientAdapter = _StubAdapter(this)
    ..options.baseUrl = 'http://localhost/api/v1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.client);

  final _VerdictApiClient client;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    client.posts++;
    return ResponseBody.fromString(
      jsonEncode(client.body),
      202,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingEmergencyRepository implements EmergencyRepository {
  _RecordingEmergencyRepository({this.fails = false, this.contactsNotified});

  final bool fails;
  final int? contactsNotified;
  final List<String> retracted = [];

  @override
  Future<RetractionOutcome> retractAlert(String incidentId) async {
    retracted.add(incidentId);
    if (fails) throw Exception('network down');
    return RetractionOutcome(
      incidentId: incidentId,
      retractedAt: DateTime.now(),
      contactsNotified: contactsNotified,
      settled: contactsNotified != null,
    );
  }

  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    String? incidentId,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async =>
      DispatchOutcome(incidentId: incidentId);

  @override
  Future<DispatchOutcome> fetchDispatchStatus(String incidentId) async =>
      DispatchOutcome(incidentId: incidentId);
}

void main() {
  group('the app noticing its own automatic alert', () {
    /// The phone only learns an automatic alert happened from the `/analyze`
    /// response. If this does not fire, a false alarm reaches her contacts and
    /// nothing in the app knows — which is the hole the retraction closes.
    test('a triggered verdict reports the incident', () async {
      final api = _VerdictApiClient({
        'auto_sos': {'triggered': true, 'incident_id': 'inc-1'},
      });
      final seen = <String>[];
      final aggregator = ThreatSignalAggregator(
        apiClient: api,
        onAutoDispatch: seen.add,
      )
        ..arm()
        ..reportGlove(0.95);

      await aggregator.flush();

      expect(seen, ['inc-1']);
    });

    test('a verdict that did not trigger reports nothing', () async {
      // `auto_sos` is always present and always a map: it reports the decision
      // *not* to dispatch too. Reading it for null would claim an alarm on
      // every single reading.
      final api = _VerdictApiClient({
        'auto_sos': {
          'triggered': false,
          'reason': 'below threshold',
          'score': 0.41,
        },
      });
      final seen = <String>[];
      final aggregator = ThreatSignalAggregator(
        apiClient: api,
        onAutoDispatch: seen.add,
      )
        ..arm()
        ..reportGlove(0.4);

      await aggregator.flush();

      expect(seen, isEmpty);
    });

    test('the same incident is reported only once', () async {
      // Readings keep flowing at one a second and the dedup window is two
      // minutes, so the response can keep naming the same incident. Without
      // this the prompt would be rebuilt sixty times a minute and her tap
      // could land on a freshly replaced widget.
      final api = _VerdictApiClient({
        'auto_sos': {'triggered': true, 'incident_id': 'inc-1'},
      });
      final seen = <String>[];
      final aggregator = ThreatSignalAggregator(
        apiClient: api,
        onAutoDispatch: seen.add,
      )
        ..arm()
        ..reportGlove(0.95);

      await aggregator.flush();
      aggregator.reportGlove(0.96);
      await aggregator.flush();
      aggregator.reportGlove(0.97);
      await aggregator.flush();

      expect(api.posts, 3);
      expect(seen, ['inc-1']);
    });

    test('a second, different incident is reported', () async {
      final api = _VerdictApiClient({
        'auto_sos': {'triggered': true, 'incident_id': 'inc-1'},
      });
      final seen = <String>[];
      final aggregator = ThreatSignalAggregator(
        apiClient: api,
        onAutoDispatch: seen.add,
      )
        ..arm()
        ..reportGlove(0.95);
      await aggregator.flush();

      final api2 = _VerdictApiClient({
        'auto_sos': {'triggered': true, 'incident_id': 'inc-2'},
      });
      final aggregator2 = ThreatSignalAggregator(
        apiClient: api2,
        onAutoDispatch: seen.add,
      )
        ..arm()
        ..reportGlove(0.95);
      await aggregator2.flush();

      expect(seen, ['inc-1', 'inc-2']);
    });

    test('a verdict with no incident id is not reported', () async {
      // There would be nothing to retract. Reporting it would offer her a
      // button that cannot work.
      final api = _VerdictApiClient({
        'auto_sos': {'triggered': true},
      });
      final seen = <String>[];
      final aggregator = ThreatSignalAggregator(
        apiClient: api,
        onAutoDispatch: seen.add,
      )
        ..arm()
        ..reportGlove(0.95);

      await aggregator.flush();

      expect(seen, isEmpty);
    });
  });

  group('standing the alert down', () {
    ProviderContainer containerWith(_RecordingEmergencyRepository repository) {
      final container = ProviderContainer(
        overrides: [
          emergencyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('nothing is offered until an automatic alert happens', () {
      final container = containerWith(_RecordingEmergencyRepository());

      final state = container.read(autoSosRetractionProvider);
      expect(state.stage, AutoSosRetractionStage.idle);
      expect(state.incidentId, isNull);
    });

    test('a dispatch offers the stand-down', () {
      final container = containerWith(_RecordingEmergencyRepository());

      container
          .read(autoSosRetractionProvider.notifier)
          .noticeDispatch('inc-1');

      final state = container.read(autoSosRetractionProvider);
      expect(state.stage, AutoSosRetractionStage.offered);
      expect(state.incidentId, 'inc-1');
      expect(state.dispatchedAt, isNotNull);
    });

    test('retracting sends it and reports how many were told', () async {
      final repository = _RecordingEmergencyRepository(contactsNotified: 2);
      final container = containerWith(repository);
      final notifier = container.read(autoSosRetractionProvider.notifier);

      notifier.noticeDispatch('inc-1');
      await notifier.retract();

      expect(repository.retracted, ['inc-1']);
      final state = container.read(autoSosRetractionProvider);
      expect(state.stage, AutoSosRetractionStage.retracted);
      expect(state.contactsNotified, 2);
    });

    test('a failure says so and keeps the action available', () async {
      // The alert is still standing. Reporting success, or clearing the
      // prompt, would leave her believing her contacts had been corrected
      // when they had not.
      final repository = _RecordingEmergencyRepository(fails: true);
      final container = containerWith(repository);
      final notifier = container.read(autoSosRetractionProvider.notifier);

      notifier.noticeDispatch('inc-1');
      await notifier.retract();

      final state = container.read(autoSosRetractionProvider);
      expect(state.stage, AutoSosRetractionStage.failed);
      expect(state.failureMessage, isNotNull);
      expect(state.incidentId, 'inc-1');

      // And it can be retried rather than being a dead end.
      notifier.retryable();
      expect(
        container.read(autoSosRetractionProvider).stage,
        AutoSosRetractionStage.offered,
      );
    });

    test('retracting with nothing offered does nothing', () async {
      final repository = _RecordingEmergencyRepository();
      final container = containerWith(repository);

      await container.read(autoSosRetractionProvider.notifier).retract();

      expect(repository.retracted, isEmpty);
    });

    test('dismissing does not retract', () {
      // A dismissed prompt is not a correction. If this cleared the incident
      // *and* told her contacts, hiding the banner would silently stand a real
      // emergency down.
      final repository = _RecordingEmergencyRepository();
      final container = containerWith(repository);
      final notifier = container.read(autoSosRetractionProvider.notifier);

      notifier.noticeDispatch('inc-1');
      notifier.dismiss();

      expect(repository.retracted, isEmpty);
      expect(
        container.read(autoSosRetractionProvider).stage,
        AutoSosRetractionStage.idle,
      );
    });

    test('a newer automatic alert replaces an older offer', () {
      // Showing a stand-down for the older incident while a newer one stands
      // would offer to correct the wrong alarm.
      final container = containerWith(_RecordingEmergencyRepository());
      final notifier = container.read(autoSosRetractionProvider.notifier);

      notifier.noticeDispatch('inc-1');
      notifier.noticeDispatch('inc-2');

      expect(container.read(autoSosRetractionProvider).incidentId, 'inc-2');
    });
  });

  group('the prompt window', () {
    test('is a minute, matching the backend constant', () {
      // Pinned on both sides: `tests/test_incident_retraction.py` asserts the
      // Python constant, and this asserts the Dart one. They are a pair.
      expect(kAutoSosRetractionPrompt, const Duration(seconds: 60));
    });
  });
}
