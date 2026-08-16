import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/feedback/sa_empty_state.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../domain/models/gps_breadcrumb.dart';

/// GPS breadcrumb trail for a report — numbered markers in chronological
/// order connected by a polyline.
///
/// Requires a Google Maps API key configured natively
/// (`android/app/src/main/AndroidManifest.xml`'s
/// `com.google.android.geo.API_KEY` meta-data, and
/// `GMSApiKey`/`GMSServices.provideAPIKey` in `ios/Runner/AppDelegate.swift`)
/// — without one, the map view renders a blank/watermarked tile grid rather
/// than real map tiles. The markers/polyline logic below is fully real and
/// works as soon as a key is added; nothing here is a placeholder.
class ReportBreadcrumbMap extends StatelessWidget {
  const ReportBreadcrumbMap({required this.breadcrumbs, super.key});

  final List<GpsBreadcrumb> breadcrumbs;

  @override
  Widget build(BuildContext context) {
    if (breadcrumbs.isEmpty) {
      return const SaEmptyState(title: 'No location trail', body: 'No GPS breadcrumbs were captured for this report.');
    }

    final points = [for (final b in breadcrumbs) LatLng(b.latitude, b.longitude)];
    final markers = {
      for (var i = 0; i < points.length; i++)
        Marker(
          markerId: MarkerId('breadcrumb-$i'),
          position: points[i],
          infoWindow: InfoWindow(title: '${i + 1}', snippet: breadcrumbs[i].timestamp),
        ),
    };

    return ClipRRect(
      borderRadius: AppRadius.xl2Radius,
      child: SizedBox(
        height: 200,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: points.first, zoom: 15),
          markers: markers,
          polylines: {
            Polyline(polylineId: const PolylineId('breadcrumb-trail'), points: points, width: 3),
          },
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          liteModeEnabled: true,
        ),
      ),
    );
  }
}

/// Export actions row — PDF export and a shareable secure link, plus a
/// truncated chain-of-custody hash for display.
class ReportExportActions extends StatelessWidget {
  const ReportExportActions({
    required this.onExportPdf,
    required this.onShareLink,
    this.chainOfCustodyHash,
    this.busy = false,
    super.key,
  });

  final VoidCallback onExportPdf;
  final VoidCallback onShareLink;
  final String? chainOfCustodyHash;

  /// An export fetches a PDF over the network and a link mints a token, so
  /// both take long enough to need saying. Without this the buttons looked
  /// inert and invited a second tap.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaButton(
          label: 'Export PDF',
          variant: SaButtonVariant.secondary,
          fullWidth: true,
          icon: const SaIcon(SaIconGlyph.download, size: 18),
          isLoading: busy,
          onPressed: busy ? null : onExportPdf,
        ),
        const SizedBox(height: AppSpacing.space3),
        SaButton(
          label: 'Share Secure Link',
          variant: SaButtonVariant.ghost,
          fullWidth: true,
          icon: const SaIcon(SaIconGlyph.link, size: 18),
          onPressed: busy ? null : onShareLink,
        ),
        if (chainOfCustodyHash != null) ...[
          const SizedBox(height: AppSpacing.space3),
          Text(
            'Chain of custody: ${chainOfCustodyHash!.substring(0, 16)}…',
            style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ],
    );
  }
}
