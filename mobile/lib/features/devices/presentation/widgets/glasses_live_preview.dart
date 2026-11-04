import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../data/glasses_preview_providers.dart';
import '../../data/mjpeg_client.dart';
import '../../data/weapon_overlay_providers.dart';
import 'weapon_detection_overlay.dart';

/// A live view of what the glasses can see.
///
/// Exists so a user can confirm the camera points where she thinks it does,
/// and so the system can be demonstrated without starting a Safe Journey —
/// until now nothing in the app ever drew a frame, because the detector
/// consumes them and produces a score.
///
/// **Off by default, and started by a deliberate tap.** The camera serves one
/// video client, streaming costs both devices battery, and a picture of a
/// woman's surroundings should appear because she asked for it rather than
/// because a sheet happened to open.
class GlassesLivePreview extends ConsumerStatefulWidget {
  const GlassesLivePreview({super.key});

  @override
  ConsumerState<GlassesLivePreview> createState() => _GlassesLivePreviewState();
}

class _GlassesLivePreviewState extends ConsumerState<GlassesLivePreview> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SaIcon(SaIconGlyph.glasses, size: 18, color: onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: Text('Live view',
                  style: AppTypography.labelL.copyWith(color: onSurface)),
            ),
            TextButton(
              onPressed: () => setState(() => _showing = !_showing),
              child: Text(
                _showing ? 'Hide' : 'Show',
                style: AppTypography.labelL.copyWith(color: AppColors.violet500),
              ),
            ),
          ],
        ),
        if (_showing) ...[
          const SizedBox(height: AppSpacing.space2),
          const _PreviewSurface(),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Not recorded. Shown only while this is open.',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ],
    );
  }
}

/// How the video is painted into the preview box.
///
/// Named once and shared with the overlay, because the two must agree. The
/// overlay undoes exactly this fit to place its boxes, so a change here that
/// did not reach the overlay would move every box off its target — silently,
/// and by an amount that depends on the device's aspect ratio.
const BoxFit _videoFit = BoxFit.cover;

class _PreviewSurface extends ConsumerWidget {
  const _PreviewSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final source = ref.watch(glassesPreviewSourceProvider);
    final frame = ref.watch(glassesPreviewFramesProvider).valueOrNull;
    final status = ref.watch(glassesPreviewStatusProvider).valueOrNull;

    final Widget body;
    if (source == null) {
      body = _Message(
        text: 'No camera paired yet.',
        onSurface: onSurface,
      );
    } else if (frame != null && status != GlassesStreamStatus.disconnected) {
      // The video and the boxes are separate layers on purpose. Painting the
      // boxes into the image would couple the overlay's rate to the video's,
      // and a slow inference would then hold up a frame that is ready to show.
      // Stacked, the video plays at whatever rate it arrives and the boxes
      // land on top of whichever frame is current.
      body = Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            frame,
            // Without this the widget blanks between frames and the preview
            // strobes instead of playing.
            gaplessPlayback: true,
            fit: _videoFit,
            width: double.infinity,
          ),
          const _DetectionLayer(fit: _videoFit),
        ],
      );
    } else if (status == GlassesStreamStatus.disconnected) {
      // Never keep showing the last frame here: a still picture presented as
      // live is the one failure mode that could tell someone she is being
      // watched over when she is not.
      body = _Message(
        text: 'Lost the camera. Retrying…',
        onSurface: onSurface,
      );
    } else {
      body = _Message(text: 'Connecting to the camera…', onSurface: onSurface);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.lgRadius,
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              color: onSurface.withValues(alpha: 0.06),
              alignment: Alignment.center,
              child: body,
            ),
          ),
        ),
        if (source != null) ...[
          const SizedBox(height: AppSpacing.space2),
          _DetectionStatus(onSurface: onSurface),
        ],
        if (source?.isShared ?? false) ...[
          const SizedBox(height: AppSpacing.space1),
          Text(
            'This is the same video weapon detection is scoring.',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ],
    );
  }
}

/// The boxes, and nothing else.
///
/// Separated from [_PreviewSurface] so that a rebuild caused by a new
/// detection repaints only this layer, leaving the `Image.memory` above it
/// untouched. Rebuilding the image on every inference would decode the JPEG
/// again five times a second for no visible change.
class _DetectionLayer extends ConsumerWidget {
  const _DetectionLayer({required this.fit});

  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(weaponOverlayStateProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();

    // Asked at paint time rather than tracked by a timer: this layer rebuilds
    // with the video, so an inference that stopped arriving ages out on the
    // next frame rather than waiting for a clock to notice.
    final visible = state.visibleAt(DateTime.now());
    if (visible.isEmpty) return const SizedBox.shrink();

    return WeaponDetectionOverlay(
      detections: visible,
      frameSize: state.frameSize,
      fit: fit,
    );
  }
}

/// A one-line statement of what the detector is doing, under the picture.
///
/// Present because a preview with no boxes is ambiguous: it could mean the
/// model looked and saw nothing, or that nothing is running at all. Those are
/// very different things for a user deciding whether to trust the system, and
/// the second one is the failure this project has hit five times.
class _DetectionStatus extends ConsumerWidget {
  const _DetectionStatus({required this.onSurface});

  final Color onSurface;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canRunWeaponDetectorOnDevice) {
      return _StatusLine(
        text: 'Weapon detection does not run on this platform.',
        colour: onSurface.withValues(alpha: 0.6),
      );
    }

    final detector = ref.watch(weaponOverlayDetectorProvider);
    if (detector == null) {
      return _StatusLine(
        text: 'Weapon detection is not running.',
        colour: onSurface.withValues(alpha: 0.6),
      );
    }

    final state = ref.watch(weaponOverlayStateProvider).valueOrNull;
    final visible = state?.visibleAt(DateTime.now()) ?? const [];
    if (visible.isEmpty) {
      // "Watching" used to be said whether or not a single frame had ever
      // reached the model. During a Safe Journey the camera is opened by a
      // trigger rather than by arming (`CameraActivationPolicy`), so the
      // ordinary case is a detector that is loaded, running and receiving
      // nothing — and this line claimed it had looked and seen a calm street.
      // That is the project's own absent-is-not-zero rule, broken in the one
      // place a person actually reads.
      final received = detector.metrics.framesReceived;
      return _StatusLine(
        text: received == 0
            ? 'No video reaching the detector yet — nothing has been examined.'
            : 'Watching — no weapon detected.',
        colour: onSurface.withValues(alpha: 0.6),
      );
    }

    final strongest = visible.reduce(
      (a, b) => b.confidence > a.confidence ? b : a,
    );
    return _StatusLine(
      text: visible.length == 1
          ? 'Weapon detected: ${strongest.label} '
              '${(strongest.confidence * 100).round()}%'
          : '${visible.length} weapons detected — strongest '
              '${strongest.label} ${(strongest.confidence * 100).round()}%',
      colour: AppColors.coral500,
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.bodyS.copyWith(color: colour),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onSurface});

  final String text;
  final Color onSurface;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.7)),
        ),
      );
}
