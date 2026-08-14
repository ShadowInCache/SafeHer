import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safeher_app/core/location/location_providers.dart';
import 'package:safeher_app/core/location/location_result.dart';
import 'package:safeher_app/core/location/location_service.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/safety/data/safety_providers.dart';
import 'package:safeher_app/features/safety/domain/models/nearby_place.dart';
import 'package:safeher_app/features/safety/domain/safety_repository.dart';
import 'package:safeher_app/features/safety/presentation/nearby_safety_screen.dart';

import '../../../test_utils/fake_safety_repository.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _FakeLocationService implements LocationService {
  _FakeLocationService(this.result);

  final LocationResult result;

  @override
  Future<LocationResult> getCurrentLocation({Duration timeLimit = const Duration(seconds: 8)}) async =>
      result;
}

const _availableFix = LocationAvailable(latitude: 12.97, longitude: 77.59, accuracyMeters: 8);

Widget _harness({
  required SafetyRepository repository,
  LocationResult location = _availableFix,
  Brightness brightness = Brightness.dark,
}) {
  return ProviderScope(
    overrides: [
      safetyRepositoryProvider.overrideWithValue(repository),
      locationServiceProvider.overrideWithValue(_FakeLocationService(location)),
    ],
    child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: '/safety/nearby',
        routes: [
          GoRoute(path: '/safety/nearby', builder: (_, __) => const NearbySafetyScreen()),
          GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home-stub'))),
        ],
      ),
    ),
  );
}

void main() {
  group('NearbySafetyScreen', () {
    testWidgets('renders_without_exception (loading state)', (tester) async {
      await tester.pumpWidget(_harness(repository: FakeSafetyRepository()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('renders real places with their true distances', (tester) async {
      await tester.pumpWidget(
        _harness(
          repository: FakeSafetyRepository(
            places: const [
              NearbyPlace(
                id: 'node/1',
                name: 'Ashok Nagar Police Station',
                category: NearbyPlaceCategory.police,
                latitude: 12.97,
                longitude: 77.60,
                distanceMetres: 575,
                phone: '+918022001100',
              ),
              NearbyPlace(
                id: 'node/2',
                name: 'St Martha\'s Hospital',
                category: NearbyPlaceCategory.hospital,
                latitude: 12.96,
                longitude: 77.58,
                distanceMetres: 1400,
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ashok Nagar Police Station'), findsOneWidget);
      expect(find.textContaining('575 m'), findsOneWidget);
      expect(find.textContaining('1.4 km'), findsOneWidget);
    });

    testWidgets('only offers Call for places that actually have a number', (tester) async {
      await tester.pumpWidget(
        _harness(
          repository: FakeSafetyRepository(
            places: const [
              NearbyPlace(
                id: 'node/1',
                name: 'With Phone',
                category: NearbyPlaceCategory.police,
                latitude: 1,
                longitude: 1,
                distanceMetres: 100,
                phone: '+911234567890',
              ),
              NearbyPlace(
                id: 'node/2',
                name: 'Without Phone',
                category: NearbyPlaceCategory.hospital,
                latitude: 1,
                longitude: 1,
                distanceMetres: 200,
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Two cards, two Directions buttons, but only one Call button.
      expect(find.text('Directions'), findsNWidgets(2));
      expect(find.text('Call'), findsOneWidget);
    });

    testWidgets('states the permission problem rather than showing an empty list', (tester) async {
      await tester.pumpWidget(
        _harness(
          repository: FakeSafetyRepository(),
          location: const LocationUnavailable(LocationFailureReason.permissionDenied),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Location permission required'), findsOneWidget);
      expect(find.textContaining('Location permission needed'), findsOneWidget);
    });

    testWidgets('distinguishes a rate limit from a genuine outage', (tester) async {
      await tester.pumpWidget(
        _harness(repository: FakeSafetyRepository(error: const NearbyRateLimitedException())),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Too many lookups right now'), findsOneWidget);
    });

    testWidgets('says nothing was found rather than implying an error', (tester) async {
      await tester.pumpWidget(_harness(repository: FakeSafetyRepository(places: const [])));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Nothing found nearby'), findsOneWidget);
      expect(find.textContaining('No mapped safety locations'), findsOneWidget);
    });

    testWidgets('filters the list by category', (tester) async {
      await tester.pumpWidget(
        _harness(
          repository: FakeSafetyRepository(
            places: const [
              NearbyPlace(
                id: 'node/1',
                name: 'A Police Station',
                category: NearbyPlaceCategory.police,
                latitude: 1,
                longitude: 1,
                distanceMetres: 100,
              ),
              NearbyPlace(
                id: 'node/2',
                name: 'A Hospital',
                category: NearbyPlaceCategory.hospital,
                latitude: 1,
                longitude: 1,
                distanceMetres: 200,
              ),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('A Hospital'), findsOneWidget);

      await tester.tap(find.text('Police').first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('A Police Station'), findsOneWidget);
      expect(find.text('A Hospital'), findsNothing);
    });

    testWidgets('renders in light mode', (tester) async {
      await tester.pumpWidget(
        _harness(repository: FakeSafetyRepository(), brightness: Brightness.light),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });
}
