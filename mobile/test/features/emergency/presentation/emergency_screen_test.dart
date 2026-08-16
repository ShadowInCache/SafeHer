import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/location/location_providers.dart';
import 'package:safeher_app/core/location/location_result.dart';
import 'package:safeher_app/core/offline/offline_queue_providers.dart';
import 'package:safeher_app/core/offline/offline_queue_service.dart';
import 'package:safeher_app/core/evidence/evidence_recorder.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/alert_channels.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';
import 'package:safeher_app/features/emergency/data/emergency_providers.dart';
import 'package:safeher_app/features/emergency/domain/emergency_repository.dart';
import 'package:safeher_app/features/emergency/domain/evidence_repository.dart';
import 'package:safeher_app/features/emergency/presentation/emergency_screen.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/safety/data/safety_providers.dart';
import 'package:safeher_app/shared/components/buttons/sa_sos_button.dart';

import '../../../test_utils/fake_auth_repository.dart';
import '../../../test_utils/fake_key_value_store.dart';
import '../../../test_utils/fake_location_service.dart';
import '../../../test_utils/fake_safety_repository.dart';
import '../../../test_utils/fake_evidence_recorder.dart';
import '../../../test_utils/offline_test_overrides.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _RecordingEmergencyRepository implements EmergencyRepository {
  _RecordingEmergencyRepository({this.outcome = const DispatchOutcome(contactsTotal: 2, contactsNotified: 2)});

  final DispatchOutcome outcome;

  final dispatched = <Map<String, Object?>>[];

  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    dispatched.add({
      'severity': severity,
      'summary': summary,
      'auto': auto,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
    });
    return outcome;
  }
}

List<Contact> _sampleContacts() => const [
  Contact(id: '1', name: 'Anika Sharma', phone: '+15550101000', relationship: 'Sister', priority: 1, confirmed: true),
  Contact(id: '2', name: 'Rahul Verma', phone: '+15550101000', relationship: 'Partner', priority: 2, confirmed: true),
];

class _FakeContactsRepository implements ContactsRepository {
  var verificationSends = <String>[];
  var verificationCodes = <String>[];

  /// Set to make [confirmVerificationCode] throw, as a wrong code does.
  bool verificationFails = false;

  @override
  Future<bool> sendVerificationCode(String id) async {
    verificationSends.add(id);
    return false;
  }

  @override
  Future<List<Contact>> confirmVerificationCode(String id, String code) async {
    verificationCodes.add(code);
    if (verificationFails) throw Exception('wrong code');
    return getContacts();
  }

  /// Defaults to "everything works" so existing tests are unaffected by the
  /// unreachable-contact warning; the settings tests override it.
  AlertChannels channels = const AlertChannels(sms: true, email: true, push: true);

  @override
  Future<AlertChannels> getAlertChannels() async => channels;

  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async => getContacts();

  _FakeContactsRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<List<Contact>> getContacts() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleContacts();
  }

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) => throw UnimplementedError();

  @override
  Future<List<Contact>> removeContact(String id) => throw UnimplementedError();

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) => throw UnimplementedError();
}

GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/emergency',
    routes: [
      GoRoute(path: '/emergency', builder: (context, state) => const EmergencyScreen()),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('home-stub'))),
    ],
  );
}

Widget _harness({
  Brightness brightness = Brightness.dark,
  ContactsRepository? repo,
  bool offline = false,
  OfflineQueueService? queueService,
  EmergencyRepository? emergencyRepo,
  FakeEvidenceRecorder? recorder,
  EvidenceRepository? evidenceRepo,
}) {
  return ProviderScope(
    overrides: [
      evidenceRecorderProvider.overrideWithValue(recorder ?? FakeEvidenceRecorder()),
      evidenceRepositoryProvider.overrideWithValue(evidenceRepo ?? FakeEvidenceRepository()),
      contactsRepositoryProvider.overrideWithValue(repo ?? _FakeContactsRepository()),
      localKeyValueStoreProvider.overrideWithValue(FakeKeyValueStore()),
      ...offlineTestOverrides(offline: offline, queueService: queueService),
      // Always overridden (not just when a test cares about the recorded
      // call) — AppConfig.useMockApi defaults to false now that every
      // feature has a real backend, so leaving this unoverridden would
      // make dispatch attempt a real Dio call against no running server.
      emergencyRepositoryProvider.overrideWithValue(emergencyRepo ?? _RecordingEmergencyRepository()),
      // The cancel flow consults the user's safety preferences (is a PIN
      // required to stand an alert down?), so this must be overridden for the
      // same reason as the repository above.
      safetyRepositoryProvider.overrideWithValue(FakeSafetyRepository()),
      // Safety preferences resolve to signed-out defaults without a session,
      // so the cancel gate needs one to be exercised at all.
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      // Deliberately the no-fix path: an SOS must dispatch without GPS, and
      // that is the state these goldens document.
      locationServiceProvider.overrideWithValue(
        FakeLocationService(const LocationUnavailable(LocationFailureReason.unavailable)),
      ),
    ],
    // Mirrors SafeHerApp priming offlineQueueDrainerProvider at the root:
    // without an early subscriber, connectivityNotifierProvider's overridden
    // stream hasn't emitted its first value by the time a real user could
    // reach the SOS button, so an offline check taken cold would race.
    child: Consumer(
      builder: (context, ref, _) {
        ref.watch(offlineQueueDrainerProvider);
        return MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          routerConfig: _buildTestRouter(),
        );
      },
    ),
  );
}

/// Holds the SOS button long enough to confirm and land on the countdown
/// stage. Flutter's own long-press recognizer needs ~500ms of stillness
/// before onLongPressStart even fires, on top of the button's own
/// 1200ms holdDuration — so this needs real margin. The breathing/hold-ring
/// animations loop, so bounded pumps only.
Future<void> _holdSos(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byType(SaSOSButton)));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('EmergencyScreen', () {
    testWidgets('renders_without_exception (pre-activation stage)', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Emergency SOS'), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('holding SOS transitions to the countdown stage', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));

      await _holdSos(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Sending alert in'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('cancelling the countdown returns to pre-activation', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);

      await tester.tap(find.text('Cancel'));
      // Cancelling now awaits the "require PIN to cancel" preference before
      // deciding, then AnimatedSwitcher runs its own 250ms transition.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Emergency SOS'), findsOneWidget);
      expect(find.text('Sending alert in'), findsNothing);
    });

    testWidgets('countdown reaching zero dispatches the alert', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);

      // 10 one-second ticks to fully elapse the countdown.
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Help is on the way'), findsOneWidget);
      expect(find.text('Sharing live location'), findsOneWidget);
    });

    testWidgets('recording starts with the countdown, not after dispatch', (tester) async {
      // FR-EMG-06 asks for capture within a second of the trigger. Starting
      // at the countdown beats that, and it covers the seconds the user
      // spent deciding — often the most telling part of a recording.
      final recorder = FakeEvidenceRecorder();
      await tester.pumpWidget(_harness(recorder: recorder));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(recorder.startCalls, 1);
      expect(recorder.isRecording, isTrue);
    });

    testWidgets('evidence is uploaded against the incident the alert created', (tester) async {
      final recorder = FakeEvidenceRecorder();
      final evidence = FakeEvidenceRepository();
      final repo = _RecordingEmergencyRepository(
        outcome: const DispatchOutcome(
          contactsTotal: 1,
          contactsNotified: 1,
          reachedContactIds: ['1'],
          incidentId: 'incident-42',
        ),
      );
      await tester.pumpWidget(
        _harness(recorder: recorder, evidenceRepo: evidence, emergencyRepo: repo),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));
      // The recorder keeps running for a window after dispatch.
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(const Duration(milliseconds: 300));

      expect(recorder.stopCalls, 1);
      expect(evidence.uploads, ['incident-42']);
      expect(find.text('Evidence saved and encrypted'), findsOneWidget);
    });

    testWidgets('a refused microphone never blocks the alert', (tester) async {
      // The alert matters more than the recording, so a permission failure
      // is reported afterwards rather than as a dialog mid-emergency.
      final recorder = FakeEvidenceRecorder(
        startFailure: const EvidenceRecorderException(
          EvidenceRecorderFailure.permissionDenied,
        ),
      );
      final repo = _RecordingEmergencyRepository();
      await tester.pumpWidget(_harness(recorder: recorder, emergencyRepo: repo));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.dispatched, hasLength(1));
      expect(find.text('Help is on the way'), findsOneWidget);
      expect(find.text('No audio evidence \u2014 microphone unavailable'), findsOneWidget);
    });

    testWidgets('web says why it cannot record rather than failing silently', (tester) async {
      final recorder = FakeEvidenceRecorder(
        supported: false,
        startFailure: const EvidenceRecorderException(EvidenceRecorderFailure.unsupported),
      );
      await tester.pumpWidget(_harness(recorder: recorder));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Audio evidence needs the SafeHer app on your phone'),
        findsOneWidget,
      );
    });

    testWidgets('a failed upload is admitted, not hidden', (tester) async {
      final recorder = FakeEvidenceRecorder();
      final evidence = FakeEvidenceRepository(shouldFail: true);
      final repo = _RecordingEmergencyRepository(
        outcome: const DispatchOutcome(
          contactsTotal: 1,
          contactsNotified: 1,
          incidentId: 'incident-42',
        ),
      );
      await tester.pumpWidget(
        _harness(recorder: recorder, evidenceRepo: evidence, emergencyRepo: repo),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(const Duration(milliseconds: 300));

      // Believing evidence exists when it does not is worse than knowing it
      // failed: it changes what she does next.
      expect(
        find.text('Evidence recorded but not uploaded \u2014 it will be lost'),
        findsOneWidget,
      );
    });

    testWidgets('an offline alert discards the recording it cannot attach', (tester) async {
      final queue = OfflineQueueService(FakeOfflineQueueBox());
      final recorder = FakeEvidenceRecorder();
      final evidence = FakeEvidenceRepository();
      await tester.pumpWidget(
        _harness(offline: true, queueService: queue, recorder: recorder, evidenceRepo: evidence),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(const Duration(milliseconds: 300));

      // No incident id exists yet, so there is nothing to attach it to.
      expect(evidence.uploads, isEmpty);
      expect(recorder.cancelCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('contacts are marked reached only when the server says so', (tester) async {
      // Regression: the dispatched view used to walk a 600ms timer down the
      // contact list, ticking each one green with no connection to whether
      // anything had been sent. On this screen that told a woman in danger
      // that her sister had been alerted when nothing had left the phone.
      final repo = _RecordingEmergencyRepository(
        outcome: const DispatchOutcome(
          contactsTotal: 2,
          contactsNotified: 1,
          reachedContactIds: ['1'],
        ),
      );
      await tester.pumpWidget(_harness(emergencyRepo: repo));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 of 2 emergency contacts alerted.'), findsOneWidget);
      // Rahul was not reached, and the screen says so rather than showing
      // him as confirmed alongside Anika.
      expect(find.text('Could not reach'), findsOneWidget);
    });

    testWidgets('reaching nobody is stated loudly, not glossed over', (tester) async {
      final repo = _RecordingEmergencyRepository(
        outcome: const DispatchOutcome(contactsTotal: 2, contactsNotified: 0),
      );
      await tester.pumpWidget(_harness(emergencyRepo: repo));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Your alert could not be delivered to anyone.'), findsOneWidget);
      // The worst outcome is a user who believes help is coming and stops
      // trying, so she is told what to do instead.
      expect(
        find.text('Nobody could be reached. Call your local emergency number now.'),
        findsOneWidget,
      );
    });

    testWidgets('every contact reached reads as such', (tester) async {
      final repo = _RecordingEmergencyRepository(
        outcome: const DispatchOutcome(
          contactsTotal: 2,
          contactsNotified: 2,
          reachedContactIds: ['1', '2'],
        ),
      );
      await tester.pumpWidget(_harness(emergencyRepo: repo));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('All 2 emergency contacts have been alerted.'), findsOneWidget);
      expect(find.text('Could not reach'), findsNothing);
    });

    testWidgets('an offline SOS says pending, never delivered', (tester) async {
      final queue = OfflineQueueService(FakeOfflineQueueBox());
      await tester.pumpWidget(_harness(offline: true, queueService: queue));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          'You are offline. Your alert is saved and will send the moment you have signal.',
        ),
        findsOneWidget,
      );
      expect(find.text('Could not reach'), findsNothing);
    });

    testWidgets('offline SOS queues the alert, then sends it once reconnected', (tester) async {
      final queue = OfflineQueueService(FakeOfflineQueueBox());
      final repo = _RecordingEmergencyRepository();
      await tester.pumpWidget(_harness(offline: true, queueService: queue, emergencyRepo: repo));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);

      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));

      // Countdown still reaches the dispatched confirmation UI immediately
      // even though the device is offline — the alert itself is queued,
      // not lost, and not blocking the on-screen "help is on the way" state.
      expect(find.text('Help is on the way'), findsOneWidget);
      expect(repo.dispatched, isEmpty);
      expect(queue.pending, hasLength(1));
      expect(queue.pending.single.actionType, 'emergency.dispatch');

      // Reconnecting drains the queue and actually sends the alert.
      await queue.drain();
      expect(repo.dispatched, hasLength(1));
      expect(repo.dispatched.single['severity'], 'critical');
      expect(queue.pending, isEmpty);
    });

    testWidgets('dispatched stage stages contacts as notified over time', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Anika Sharma'), findsOneWidget);
      expect(find.text('Rahul Verma'), findsOneWidget);

      // Let both staggered notify timers (600ms apart) fire.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
    });

    testWidgets('marking safe requires a second confirm tap and shows cancelled stage', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));

      await tester.ensureVisible(find.text("I'm Safe — Cancel Alert"));
      await tester.pump();
      await tester.tap(find.text("I'm Safe — Cancel Alert"));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tap again to confirm'), findsOneWidget);

      await tester.tap(find.text('Tap again to confirm'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text("You're marked as safe"), findsOneWidget);
    });

    testWidgets('navigation_actions_work: Return Home navigates to /home', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text("I'm Safe — Cancel Alert"));
      await tester.pump();
      await tester.tap(find.text("I'm Safe — Cancel Alert"));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Tap again to confirm'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Return Home'));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('navigation_actions_work: close button returns to home from pre-activation', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('close button is inert during countdown and dispatched stages', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);

      // Faded out via AnimatedOpacity + wrapped in IgnorePointer rather
      // than removed, so it stays in the tree but can't be tapped.
      final ignorePointer = tester.widget<IgnorePointer>(
        find.ancestor(of: find.byTooltip('Close'), matching: find.byType(IgnorePointer)).first,
      );
      expect(ignorePointer.ignoring, isTrue);
    });

    testWidgets('renders_empty_state: contact load failure does not crash dispatched stage', (tester) async {
      await tester.pumpWidget(_harness(repo: _FakeContactsRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load emergency contacts."), findsOneWidget);
    });

    testGoldens('golden - pre-activation light', (tester) async {
      await tester.pumpWidgetBuilder(_harness(brightness: Brightness.light), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'emergency_screen_pre_activation_light',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - pre-activation dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(
        tester,
        'emergency_screen_pre_activation_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - countdown', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      // Let the AnimatedSwitcher crossfade from stage 1 fully settle.
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(
        tester,
        'emergency_screen_countdown_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - dispatched', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 1500));
      await screenMatchesGolden(
        tester,
        'emergency_screen_dispatched_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });

    testGoldens('golden - cancelled', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 11; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text("I'm Safe — Cancel Alert"));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Tap again to confirm'));
      await tester.pump(const Duration(milliseconds: 300));
      // Let the AnimatedSwitcher crossfade from stage 3 fully settle.
      await tester.pump(const Duration(milliseconds: 300));
      await screenMatchesGolden(
        tester,
        'emergency_screen_cancelled_dark',
        customPump: (tester) async => tester.pump(const Duration(milliseconds: 100)),
      );
    });
  });
}
