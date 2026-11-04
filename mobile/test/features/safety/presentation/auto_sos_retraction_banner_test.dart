import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/emergency/data/emergency_providers.dart';
import 'package:safeher_app/features/emergency/domain/emergency_repository.dart';
import 'package:safeher_app/features/safety/data/auto_sos_retraction.dart';
import 'package:safeher_app/features/safety/presentation/widgets/auto_sos_retraction_banner.dart';

class _StubEmergencyRepository implements EmergencyRepository {
  _StubEmergencyRepository({this.fails = false, this.contactsNotified = 2});

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
      settled: true,
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
  Future<ProviderContainer> pump(
    WidgetTester tester,
    _StubEmergencyRepository repository,
  ) async {
    final container = ProviderContainer(
      overrides: [emergencyRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AutoSosRetractionBanner(
            child: Scaffold(body: Text('the app')),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('nothing is shown until SafeHer raises an alert itself',
      (tester) async {
    await pump(tester, _StubEmergencyRepository());

    expect(find.text('the app'), findsOneWidget);
    expect(find.textContaining('alerted your contacts'), findsNothing);
  });

  testWidgets('an automatic alert offers the stand-down', (tester) async {
    final container = await pump(tester, _StubEmergencyRepository());

    container.read(autoSosRetractionProvider.notifier).noticeDispatch('inc-1');
    await tester.pump();

    // The wording has to say the alert already went out. Auto-SOS has no
    // countdown, so anything that reads like "are you ok?" would imply her
    // contacts had not been told yet, when they had.
    expect(find.text('SafeHer alerted your contacts'), findsOneWidget);
    expect(find.textContaining("I'm safe"), findsOneWidget);
    expect(find.textContaining('automatically'), findsOneWidget);
  });

  testWidgets('tapping it sends the correction and says how many were told',
      (tester) async {
    final repository = _StubEmergencyRepository(contactsNotified: 2);
    final container = await pump(tester, repository);

    container.read(autoSosRetractionProvider.notifier).noticeDispatch('inc-1');
    await tester.pump();
    await tester.tap(find.textContaining("I'm safe"));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.retracted, ['inc-1']);
    expect(find.text('False alarm sent'), findsOneWidget);
    expect(find.textContaining('Told 2 contacts'), findsOneWidget);
  });

  testWidgets('a failure says the alert still stands', (tester) async {
    final repository = _StubEmergencyRepository(fails: true);
    final container = await pump(tester, repository);

    container.read(autoSosRetractionProvider.notifier).noticeDispatch('inc-1');
    await tester.pump();
    await tester.tap(find.textContaining("I'm safe"));
    await tester.pumpAndSettle();

    // The important half is the second sentence. A soft "something went
    // wrong" would leave her believing her contacts had been corrected.
    expect(find.text('Could not cancel'), findsOneWidget);
    expect(
      find.textContaining('still think you need help'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a failure can be retried', (tester) async {
    final repository = _StubEmergencyRepository(fails: true);
    final container = await pump(tester, repository);

    container.read(autoSosRetractionProvider.notifier).noticeDispatch('inc-1');
    await tester.pump();
    await tester.tap(find.textContaining("I'm safe"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(repository.retracted, ['inc-1', 'inc-1']);
  });

  testWidgets('hiding the banner does not stand the alert down',
      (tester) async {
    // A dismissed prompt is not a correction. If closing it retracted, she
    // could stand a real emergency down by tidying her screen.
    final repository = _StubEmergencyRepository();
    final container = await pump(tester, repository);

    container.read(autoSosRetractionProvider.notifier).noticeDispatch('inc-1');
    await tester.pump();
    await tester.tap(find.byTooltip('Hide'));
    await tester.pumpAndSettle();

    expect(repository.retracted, isEmpty);
    expect(find.text('SafeHer alerted your contacts'), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('the countdown shown is the prompt window', (tester) async {
    final container = await pump(tester, _StubEmergencyRepository());

    container.read(autoSosRetractionProvider.notifier).noticeDispatch('inc-1');
    await tester.pump();

    expect(
      find.textContaining("${kAutoSosRetractionPrompt.inSeconds}s"),
      findsOneWidget,
    );
  });

  testWidgets('the banner retires once the prompt window closes',
      (tester) async {
    final container = await pump(tester, _StubEmergencyRepository());

    // Dispatched a full window ago: the prompt is spent. What expires is the
    // banner, not her ability to retract — the server takes a stand-down
    // whenever it arrives.
    container.read(autoSosRetractionProvider.notifier).noticeDispatch(
          'inc-1',
          at: DateTime.now().subtract(
            kAutoSosRetractionPrompt + const Duration(seconds: 1),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('SafeHer alerted your contacts'), findsNothing);
    expect(
      container.read(autoSosRetractionProvider).stage,
      AutoSosRetractionStage.idle,
    );
  });
}
