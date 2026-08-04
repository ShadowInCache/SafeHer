import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/emergency/data/emergency_providers.dart';
import 'package:safeher_app/features/emergency/domain/emergency_repository.dart';
import 'package:safeher_app/features/emergency/domain/models/emergency_contact_summary.dart';
import 'package:safeher_app/features/emergency/presentation/emergency_screen.dart';
import 'package:safeher_app/shared/components/buttons/sa_sos_button.dart';

List<EmergencyContactSummary> _sampleContacts() => const [
  EmergencyContactSummary(id: '1', name: 'Anika Sharma', relationship: 'Sister', priority: 1),
  EmergencyContactSummary(id: '2', name: 'Rahul Verma', relationship: 'Partner', priority: 2),
];

class _FakeEmergencyRepository implements EmergencyRepository {
  _FakeEmergencyRepository({this.shouldFail = false});
  final bool shouldFail;

  @override
  Future<List<EmergencyContactSummary>> getEmergencyContacts() async {
    await Future.delayed(const Duration(milliseconds: 50));
    if (shouldFail) throw Exception('network error');
    return _sampleContacts();
  }
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

Widget _harness({Brightness brightness = Brightness.dark, EmergencyRepository? repo}) {
  return ProviderScope(
    overrides: [emergencyRepositoryProvider.overrideWithValue(repo ?? _FakeEmergencyRepository())],
    child: MaterialApp.router(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: _buildTestRouter(),
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
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('cancelling the countdown returns to pre-activation', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);

      await tester.tap(find.text('Cancel'));
      // AnimatedSwitcher keeps the outgoing child around for its own
      // 250ms transition.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Emergency SOS'), findsOneWidget);
      expect(find.text('Sending alert in'), findsNothing);
    });

    testWidgets('countdown reaching zero dispatches the alert', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);

      // 5 one-second ticks to fully elapse the countdown.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Help is on the way'), findsOneWidget);
      expect(find.text('Sharing live location'), findsOneWidget);
    });

    testWidgets('dispatched stage stages contacts as notified over time', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 6; i++) {
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
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));

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
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(milliseconds: 100));
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
      await tester.pumpWidget(_harness(repo: _FakeEmergencyRepository(shouldFail: true)));
      await tester.pump(const Duration(milliseconds: 100));
      await _holdSos(tester);
      for (var i = 0; i < 6; i++) {
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
      for (var i = 0; i < 6; i++) {
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
      for (var i = 0; i < 6; i++) {
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
