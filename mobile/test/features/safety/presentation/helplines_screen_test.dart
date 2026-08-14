import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/domain/models/helpline.dart';
import 'package:safeher_app/features/safety/domain/models/safety_guide.dart';
import 'package:safeher_app/features/safety/presentation/helplines_screen.dart';
import 'package:safeher_app/features/safety/presentation/safety_guides_screen.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

Widget _harness(Widget screen, {Brightness brightness = Brightness.dark}) {
  return MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    routerConfig: GoRouter(
      initialLocation: '/screen',
      routes: [
        GoRoute(path: '/screen', builder: (_, __) => screen),
        GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home-stub'))),
      ],
    ),
  );
}

void main() {
  group('IndiaHelplines data', () {
    test('every number is digits only and every entry records its provenance', () {
      expect(IndiaHelplines.all, isNotEmpty);
      for (final helpline in IndiaHelplines.all) {
        expect(
          RegExp(r'^\d{3,4}$').hasMatch(helpline.number),
          isTrue,
          reason: '${helpline.name} has a malformed number: ${helpline.number}',
        );
        expect(helpline.source, isNotEmpty, reason: '${helpline.name} has no source');
        expect(helpline.lastVerified, isNotEmpty, reason: '${helpline.name} has no verified date');
      }
    });

    test('numbers are unique', () {
      final numbers = IndiaHelplines.all.map((h) => h.number).toList();
      expect(numbers.toSet().length, numbers.length);
    });

    test('includes the single national emergency number', () {
      expect(IndiaHelplines.all.any((h) => h.number == '112' && h.isPrimary), isTrue);
    });
  });

  group('HelplinesScreen', () {
    testWidgets('lists every helpline with its number', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(const HelplinesScreen()));
      await tester.pump();

      for (final helpline in IndiaHelplines.all) {
        expect(find.text(helpline.name), findsOneWidget);
        expect(find.text(helpline.number), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('states the country scope so the numbers are not misread', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(const HelplinesScreen()));
      await tester.pump();

      expect(find.textContaining('National helplines for India'), findsOneWidget);
      expect(find.textContaining('Outside India'), findsOneWidget);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(_harness(const HelplinesScreen(), brightness: Brightness.light));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('SafetyGuidesScreen', () {
    test('every guide has content', () {
      expect(SafetyGuides.all, isNotEmpty);
      for (final guide in SafetyGuides.all) {
        expect(guide.title, isNotEmpty);
        expect(guide.summary, isNotEmpty);
        expect(guide.points, isNotEmpty, reason: '${guide.id} has no points');
      }
    });

    test('guide ids are unique', () {
      final ids = SafetyGuides.all.map((g) => g.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    testWidgets('renders_without_exception and lists guides', (tester) async {
      await tester.pumpWidget(_harness(const SafetyGuidesScreen()));
      await tester.pump();

      expect(find.text('Safety & Awareness'), findsOneWidget);
      expect(find.text(SafetyGuides.all.first.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expands a guide to reveal its points', (tester) async {
      await tester.pumpWidget(_harness(const SafetyGuidesScreen()));
      await tester.pump();

      final first = SafetyGuides.all.first;
      await tester.tap(find.text(first.title));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(first.points.first), findsOneWidget);
    });

    testWidgets('filters by category', (tester) async {
      await tester.pumpWidget(_harness(const SafetyGuidesScreen()));
      await tester.pump();

      await tester.tap(find.text(SafetyGuideCategory.travel.label).first);
      await tester.pump(const Duration(milliseconds: 300));

      final travelGuides = SafetyGuides.byCategory(SafetyGuideCategory.travel);
      expect(travelGuides, isNotEmpty);
      expect(find.text(travelGuides.first.title), findsOneWidget);
    });
  });
}
