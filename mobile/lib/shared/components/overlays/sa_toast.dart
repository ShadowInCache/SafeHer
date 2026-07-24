import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';
import '../icons/sa_icon.dart';

enum SaToastType { success, error, info }

extension on SaToastType {
  Color color() => switch (this) {
    SaToastType.success => AppColors.success500,
    SaToastType.error => AppColors.coral500,
    SaToastType.info => AppColors.violet500,
  };

  SaIconGlyph icon() => switch (this) {
    SaToastType.success => SaIconGlyph.check,
    SaToastType.error => SaIconGlyph.close,
    SaToastType.info => SaIconGlyph.bell,
  };
}

/// The toast's visual content, exposed separately so it can be rendered
/// (and golden-tested) without going through the Overlay machinery.
class SaToastCard extends StatelessWidget {
  const SaToastCard({required this.message, super.key, this.type = SaToastType.info});

  final String message;
  final SaToastType type;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
        decoration: BoxDecoration(
          color: saColors.surfaceElevated,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: type.color().withValues(alpha: 0.4)),
          boxShadow: saColors.shadowLevel4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaIcon(type.icon(), size: 18, color: type.color()),
            const SizedBox(width: AppSpacing.space2),
            Flexible(
              child: Text(
                message,
                style: AppTypography.bodyM.copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inserts a top-sliding, auto-dismissing toast into the nearest [Overlay].
void showSaToast(
  BuildContext context, {
  required String message,
  SaToastType type = SaToastType.info,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(
    builder: (ctx) => _SaToastOverlay(message: message, type: type, duration: duration),
  );
  overlay.insert(entry);
  Future.delayed(duration + const Duration(milliseconds: 250), () {
    if (entry.mounted) entry.remove();
  });
}

class _SaToastOverlay extends StatefulWidget {
  const _SaToastOverlay({required this.message, required this.type, required this.duration});

  final String message;
  final SaToastType type;
  final Duration duration;

  @override
  State<_SaToastOverlay> createState() => _SaToastOverlayState();
}

class _SaToastOverlayState extends State<_SaToastOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AnimationHelpers.forward(context, _controller);
    });
    Future.delayed(widget.duration, () {
      if (mounted) AnimationHelpers.reverse(context, _controller);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + AppSpacing.space3,
      left: AppSpacing.space4,
      right: AppSpacing.space4,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.5), end: Offset.zero).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        ),
        child: SaToastCard(message: widget.message, type: widget.type),
      ),
    );
  }
}
