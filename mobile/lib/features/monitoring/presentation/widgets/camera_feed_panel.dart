import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/icons/sa_icon.dart';

/// Camera feed panel for the Live Monitoring screen. In the connected
/// state this will render the glasses' MJPEG stream with detection-box
/// overlays (Phase 4); today's mock never reports glasses connected, so
/// only the "not connected" placeholder state is built.
class CameraFeedPanel extends StatelessWidget {
  const CameraFeedPanel({required this.glassesConnected, super.key});

  final bool glassesConnected;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaCard(
      semanticsLabel: glassesConnected ? 'Camera feed, glasses connected' : 'Camera feed, glasses not connected',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Camera', style: AppTypography.headingS.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space3),
          Expanded(
            child: glassesConnected ? const _ConnectedPlaceholder() : const _NotConnectedPlaceholder(),
          ),
        ],
      ),
    );
  }
}

class _NotConnectedPlaceholder extends StatelessWidget {
  const _NotConnectedPlaceholder();

  static const _fullLayoutMinHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this height (small phones / dense grid rows) the icon +
        // text + button stack no longer fits — collapse to a single
        // tappable row instead of letting the column overflow.
        if (constraints.maxHeight < _fullLayoutMinHeight) {
          return Center(
            child: InkWell(
              onTap: () => context.push('/devices'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SaIcon(SaIconGlyph.glasses, size: 20, color: onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: AppSpacing.space2),
                  Flexible(
                    child: Text(
                      'Connect glasses',
                      style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.6)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SaIcon(SaIconGlyph.glasses, size: 48, color: onSurface.withValues(alpha: 0.4)),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'Glasses not connected',
                style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: AppSpacing.space4),
              SaButton(
                label: 'Connect glasses',
                size: SaButtonSize.sm,
                variant: SaButtonVariant.secondary,
                onPressed: () => context.push('/devices'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConnectedPlaceholder extends StatelessWidget {
  const _ConnectedPlaceholder();

  @override
  Widget build(BuildContext context) {
    // Live MJPEG stream + detection overlays land in Phase 4 alongside the
    // real device API; this branch is unreachable from today's mock stream.
    return const SizedBox.shrink();
  }
}
