import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/premium_theme.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/widgets/glass_card.dart';

class LiveTrackingMapScreenV2 extends ConsumerWidget {
  const LiveTrackingMapScreenV2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final current = LatLng(
      safety.currentLocation.latitude,
      safety.currentLocation.longitude,
    );

    final markers = {
      Marker(
        markerId: const MarkerId('you'),
        position: current,
        infoWindow: const InfoWindow(title: 'You'),
      ),
      Marker(
        markerId: const MarkerId('police'),
        position: LatLng(current.latitude + 0.01, current.longitude + 0.008),
        infoWindow: const InfoWindow(title: 'Nearest Police Station'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ),
      Marker(
        markerId: const MarkerId('hospital'),
        position: LatLng(current.latitude - 0.008, current.longitude + 0.004),
        infoWindow: const InfoWindow(title: 'Nearby Hospital'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('shelter'),
        position: LatLng(current.latitude + 0.006, current.longitude - 0.005),
        infoWindow: const InfoWindow(title: 'Women Shelter'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      ),
    };

    final route = [
      current,
      LatLng(current.latitude + 0.002, current.longitude + 0.002),
      LatLng(current.latitude + 0.004, current.longitude + 0.001),
      LatLng(current.latitude + 0.006, current.longitude - 0.001),
    ];

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: current, zoom: 15.3),
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            circles: {
              Circle(
                circleId: const CircleId('geofence'),
                center: current,
                radius: 350,
                strokeColor: PremiumTheme.accent,
                fillColor: PremiumTheme.accent.withValues(alpha: 0.12),
              ),
            },
            polylines: {
              Polyline(
                polylineId: const PolylineId('history'),
                points: route,
                color: PremiumTheme.accent,
                width: 5,
              ),
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.of(context).padding.top + 10,
            child: GlassCard(
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: PremiumTheme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Live tracking enabled • Crime hotspot-aware route recommendations active',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Live Safety Navigation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Nearest safe place ETA: 6 mins'),
                  const Text('Route risk score: 22/100 (low)'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            ref
                                .read(safetyControllerProvider.notifier)
                                .setGuardianMode(!safety.guardianMode);
                          },
                          icon: const Icon(Icons.group_outlined),
                          label: Text(
                            safety.guardianMode
                                ? 'Disable Family Live Tracking'
                                : 'Enable Family Live Tracking',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
