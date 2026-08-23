import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/animations/animation_tokens.dart';
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

  /// Read aloud before the message, so a screen-reader user learns whether
  /// something succeeded or failed before hearing what it was about.
  String semanticPrefix() => switch (this) {
    SaToastType.success => 'Success',
    SaToastType.error => 'Error',
    SaToastType.info => 'Notice',
  };
}

/// The toast's visual content, exposed separately so it can be rendered
/// (and golden-tested) without going through the Overlay machinery.
///
/// The glass treatment matches [SaCard] and the dialogs: a blurred
/// translucent surface, a hairline border tinted by severity, and a colour
/// accent down the leading edge that identifies the toast's kind at a
/// glance without relying on the icon alone.
class SaToastCard extends StatelessWidget {
  const SaToastCard({
    required this.message,
    super.key,
    this.type = SaToastType.info,
    this.title,
    this.onDismiss,
  });

  final String message;
  final SaToastType type;

  /// Optional headline above [message]. Use it when the message alone is
  /// too terse to act on ("Incorrect email or password." reads far better
  /// under a "Couldn't sign you in" heading).
  final String? title;

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = type.color();

    return Semantics(
      liveRegion: true,
      label: '${type.semanticPrefix()}. ${title == null ? '' : '$title. '}$message',
      child: ClipRRect(
        borderRadius: AppRadius.lgRadius,
        child: Container(
          decoration: BoxDecoration(
            color: saColors.surfaceElevated,
            borderRadius: AppRadius.lgRadius,
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: saColors.shadowLevel4,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Severity spine. Colour alone never carries the meaning
                // — the icon and the spoken prefix do too — but it makes
                // the kind readable in peripheral vision.
                Container(width: 4, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space4,
                      vertical: AppSpacing.space3,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SaIcon(type.icon(), size: 15, color: accent),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space3),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title != null) ...[
                                Text(
                                  title!,
                                  style: AppTypography.labelL.copyWith(color: onSurface),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                message,
                                style: AppTypography.bodyM.copyWith(
                                  color: title == null
                                      ? onSurface
                                      : onSurface.withValues(alpha: 0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onDismiss != null) ...[
                          const SizedBox(width: AppSpacing.space2),
                          Semantics(
                            button: true,
                            label: 'Dismiss',
                            child: GestureDetector(
                              onTap: onDismiss,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                // Pads a 15dp glyph out to a 44dp target
                                // without moving it visually.
                                padding: const EdgeInsets.all(AppSpacing.space2),
                                child: SaIcon(
                                  SaIconGlyph.close,
                                  size: 15,
                                  color: onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        )
      ),
    );
  }
}

/// Inserts a top-sliding, auto-dismissing toast into the nearest [Overlay].
///
/// Only one toast is on screen at a time: a second call replaces the first
/// rather than stacking, so a burst of failures can't bury the screen.
void showSaToast(
  BuildContext context, {
  required String message,
  SaToastType type = SaToastType.info,
  String? title,
  Duration duration = const Duration(seconds: 4),
}) {
  final overlay = Overlay.of(context);

  // `mounted` guard, not a bare remove(): the previous entry may belong to
  // an Overlay that has since been torn down — navigating away and showing
  // another toast is enough — and OverlayEntry.remove() asserts when it is
  // called twice. That threw before the replacement toast could be shown,
  // so the user saw nothing at all.
  final previous = _activeToast;
  if (previous != null && previous.mounted) previous.remove();
  _activeToast = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _SaToastOverlay(
      message: message,
      title: title,
      type: type,
      duration: duration,
      onDismissed: () {
        if (entry.mounted) entry.remove();
        if (identical(_activeToast, entry)) _activeToast = null;
      },
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);

  if (type == SaToastType.error) {
    // Errors get a haptic bump: a user glancing away from a phone in her
    // pocket still learns the alert didn't send.
    HapticFeedback.mediumImpact();
  }
}

OverlayEntry? _activeToast;

class _SaToastOverlay extends StatefulWidget {
  const _SaToastOverlay({
    required this.message,
    required this.title,
    required this.type,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final String? title;
  final SaToastType type;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_SaToastOverlay> createState() => _SaToastOverlayState();
}

class _SaToastOverlayState extends State<_SaToastOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AnimationTokens.standard,
  );

  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AnimationHelpers.forward(context, _controller);
    });
    Future.delayed(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    await AnimationHelpers.reverse(context, _controller);
    // The entry outlives this State, so removal is the caller's job — but
    // only once the exit animation has actually finished, or the toast
    // vanishes mid-slide.
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    return Positioned(
      top: MediaQuery.of(context).padding.top + AppSpacing.space3,
      left: AppSpacing.space4,
      right: AppSpacing.space4,
      // Overlay entries have no Material ancestor of their own. Without
      // this, every Text inside renders with the debug double-underline
      // and no default text style — which is exactly how this toast used
      // to look on screen.
      child: Material(
        type: MaterialType.transparency,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1.5),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: Dismissible(
              key: const ValueKey('sa-toast'),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismissed(),
              child: SaToastCard(
                message: widget.message,
                title: widget.title,
                type: widget.type,
                onDismiss: _dismiss,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
