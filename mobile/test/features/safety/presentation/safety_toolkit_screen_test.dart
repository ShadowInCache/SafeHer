import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/presentation/safety_toolkit_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

/// Golden coverage for the safety toolkit hub -- the grid of tools. It watches
/// no providers (actions fire on tap), so rendering needs only a router.
Widget _harness({Brightness brightness = Brightness.dark}) {
  final router = GoRouter(
    initialLocation: '/safety',
    routes: [
      GoRoute(path: '/safety', builder: (_, __) => const SafetyToolkitScreen()),
      GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home'))),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: router,
      builder: (context, child) =>
          SaAmbientBackground(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  group('SafetyToolkitScreen', () {
    testWidgets('renders without exception', (tester) async {
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
      await screenMatchesGolden(tester, 'safety_toolkit_screen_light');
    });

    testGoldens('golden - dark', (tester) async {
      await tester.pumpWidgetBuilder(_harness(), surfaceSize: const Size(390, 844));
      await tester.pump(const Duration(milliseconds: 100));
      await screenMatchesGolden(tester, 'safety_toolkit_screen_dark');
    });
  });
}
