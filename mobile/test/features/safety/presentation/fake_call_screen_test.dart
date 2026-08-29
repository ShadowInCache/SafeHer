import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/presentation/fake_call_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

/// Golden coverage for the fake-call setup screen -- the tool that stages an
/// incoming call to give someone a reason to leave.
///
/// Only the setup state is captured. Scheduling starts a periodic timer and
/// transitions to a full-screen ringing view; the timer is a test hazard and
/// the ringing screen changes every second, so a stable golden is the initial
/// state, which is also the one a user sees first. The timer is null until a
/// button is tapped, so nothing leaks at teardown.
Widget _harness({Brightness brightness = Brightness.dark}) {
  final router = GoRouter(
    initialLocation: '/safety/fake-call',
    routes: [
      GoRoute(path: '/safety/fake-call', builder: (_, __) => const FakeCallScreen()),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home'))),
    ],
  );
  return MaterialApp.router(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    routerConfig: router,
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
  );
}

void main() {
  group('FakeCallScreen', () {
    testWidgets('renders the setup state without exception or leaked timer', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(brightness: Brightness.light),
        surfaceSize: const Size(390, 844),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(tester, 'fake_call_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(tester, 'fake_call_screen_dark');
    });
  });
}
