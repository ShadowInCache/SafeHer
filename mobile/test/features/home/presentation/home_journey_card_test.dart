import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/features/home/presentation/widgets/home_journey_card.dart';
import 'package:safeher_app/features/safety/domain/models/safe_journey.dart';

import '../../../test_utils/widget_test_helpers.dart';

/// Starting a Safe Journey arms the microphone, the camera policy and the
/// glove pipeline — it is what turns the app on. It used to sit four taps deep
/// under Profile → Settings → Safety Toolkit → Safe Journey, which is the
/// wrong place for the thing you reach for on your way out of the door.
void main() {
  SafeJourney journey({
    JourneyStatus status = JourneyStatus.active,
    Duration remaining = const Duration(minutes: 12),
    String destination = 'Office',
  }) {
    final now = DateTime.now();
    return SafeJourney(
      id: 'j1',
      destinationLabel: destination,
      expectedDurationMinutes: 15,
      status: status,
      startedAt: now,
      expectedArrivalAt: now.add(remaining),
      contactIds: const [],
    );
  }

  Future<void> pump(WidgetTester tester, SafeJourney? value, VoidCallback onTap) {
    return tester.pumpWidget(
      wrapWithTheme(HomeJourneyCard(journey: value, onTap: onTap)),
    );
  }

  testWidgets('offers to start when no journey is running', (tester) async {
    await pump(tester, null, () {});

    expect(find.text('Start Safe Journey'), findsOneWidget);
    expect(find.text('Journey active'), findsNothing);
  });

  testWidgets('says what starting one actually does', (tester) async {
    await pump(tester, null, () {});

    // The card is the first thing most users will read about this feature, so
    // it names the consequence rather than just the action.
    expect(
      find.textContaining("tells your contacts if you don't arrive"),
      findsOneWidget,
    );
  });

  testWidgets('shows the destination and time left while active', (tester) async {
    await pump(tester, journey(destination: 'Library'), () {});

    expect(find.text('Journey active'), findsOneWidget);
    expect(find.textContaining('Library'), findsOneWidget);
    expect(find.textContaining('m left'), findsOneWidget);
  });

  testWidgets('an overdue journey says so rather than counting backwards',
      (tester) async {
    await pump(
      tester,
      journey(status: JourneyStatus.overdue, remaining: const Duration(minutes: -3)),
      () {},
    );

    expect(find.textContaining('overdue'), findsOneWidget);
  });

  testWidgets('a finished journey falls back to the start state', (tester) async {
    // `arrived` and `cancelled` are not in progress, so the card must offer to
    // start a new one rather than claiming one is running.
    await pump(tester, journey(status: JourneyStatus.arrived), () {});

    expect(find.text('Start Safe Journey'), findsOneWidget);
    expect(find.text('Journey active'), findsNothing);
  });

  testWidgets('tapping fires the callback', (tester) async {
    var taps = 0;
    await pump(tester, null, () => taps++);

    await tester.tap(find.byType(HomeJourneyCard));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('carries a semantics label for screen readers', (tester) async {
    // The visible text alone reads as a bare label out of context, so the
    // card announces what tapping it will do.
    Finder labelled(String label) => find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        );

    await pump(tester, null, () {});
    expect(labelled('Start a Safe Journey'), findsOneWidget);

    await pump(tester, journey(), () {});
    expect(labelled('Open your active Safe Journey'), findsOneWidget);
  });
}
