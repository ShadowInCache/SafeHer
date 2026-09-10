import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/presentation/helplines_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

/// First golden coverage for the safety toolkit. These eight screens had none,
/// which meant a layout regression in the part of the app someone reaches for
/// in a crisis would have shipped silently.
///
/// Helplines is static content -- the India emergency numbers -- so it needs
/// no providers, only a router for its back button.
Widget _harness({Brightness brightness = Brightness.dark}) {
  final router = GoRouter(
    initialLocation: '/safety/helplines',
    routes: [
      GoRoute(path: '/safety/helplines', builder: (_, __) => const HelplinesScreen()),
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
  group('HelplinesScreen', () {
    testWidgets('renders without exception', (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // The whole point of this screen: the numbers are actually present.
      expect(find.textContaining('112'), findsWidgets);
    });

    testGoldens('golden - light', (tester) async {
      await tester.pumpWidgetBuilder(
        _harness(brightness: Brightness.light),
        surfaceSize: const Size(390, 844),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(tester, 'helplines_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(tester, 'helplines_screen_dark');
    });
  });
}
