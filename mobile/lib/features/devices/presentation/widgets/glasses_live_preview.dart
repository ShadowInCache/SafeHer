import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../data/glasses_preview_providers.dart';
import '../../data/mjpeg_client.dart';

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
      body = Image.memory(
        frame,
        // Without this the widget blanks between frames and the preview
        // strobes instead of playing.
        gaplessPlayback: true,
        fit: BoxFit.cover,
        width: double.infinity,
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
        if (source?.isShared ?? false) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            'This is the same video weapon detection is scoring.',
            style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ],
    );
  }
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
