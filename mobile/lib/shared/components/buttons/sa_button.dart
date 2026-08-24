import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/theme_extensions.dart';

enum SaButtonVariant { primary, secondary, ghost, danger, inverse, inverseOutline }

enum SaButtonSize { sm, md, lg }

extension on SaButtonSize {
  double get height => switch (this) {
    SaButtonSize.sm => 36,
    SaButtonSize.md => 44,
    SaButtonSize.lg => 54,
  };

  TextStyle get labelStyle => switch (this) {
    SaButtonSize.sm => AppTypography.labelM,
    SaButtonSize.md => AppTypography.labelL,
    SaButtonSize.lg => AppTypography.labelL,
  };

  double get horizontalPadding => switch (this) {
    SaButtonSize.sm => AppSpacing.space3,
    SaButtonSize.md => AppSpacing.space4,
    SaButtonSize.lg => AppSpacing.space6,
  };
}

/// SafeHer primary button component. Supports the primary/secondary/ghost/
/// danger variants from the component library spec. For the icon-only
/// button see [SaIconButton]; for the emergency hold-to-confirm button see
/// SaSOSButton.
///
/// Press/release, loading, and disabled behavior all follow the spec:
/// press scales to 0.96 over 100ms easeOut, release springs 1.02→1.0 over
/// 150ms elasticOut, loading crossfades label↔spinner over 150ms, and
/// disabled renders at 40% opacity with interaction disabled.
class SaButton extends StatefulWidget {
  const SaButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = SaButtonVariant.primary,
    this.size = SaButtonSize.md,
    this.isLoading = false,
    this.fullWidth = false,
    this.confirmRequired = false,
    this.icon,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final SaButtonVariant variant;
  final SaButtonSize size;
  final bool isLoading;
  final bool fullWidth;

  /// When true, the first tap arms the button ("Tap again to confirm")
  /// instead of firing [onPressed]; a second tap within 3s confirms the
  /// action.
  ///
  /// The guard follows this flag alone, not the variant. Most callers pair it
  /// with [SaButtonVariant.danger], but "I'm Safe -- Cancel Alert" on the
  /// dispatched emergency screen is [SaButtonVariant.inverseOutline] -- it
  /// sits on the red emergency field, where a red button would vanish -- and
  /// it needs the two-tap guard more than anything else in the app.
  final bool confirmRequired;
  final Widget? icon;
  final String? semanticsLabel;

  @override
  State<SaButton> createState() => _SaButtonState();
}

class _SaButtonState extends State<SaButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  bool _armed = false;
  Timer? _armTimer;

  bool get _disabled => widget.onPressed == null || widget.isLoading;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _pressController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (_disabled) return;
    AnimationHelpers.forward(context, _pressController);
  }

  void _onTapCancel() {
    if (_disabled) return;
    AnimationHelpers.reverse(context, _pressController);
  }

  void _onTapUp(TapUpDetails details) {
    if (_disabled) return;
    AnimationHelpers.reverse(context, _pressController);
  }

  void _handleTap() {
    if (_disabled) return;
    // Gated on the caller's intent, not on the colour. This used to also
    // require `variant == danger`, which meant `confirmRequired: true` on any
    // other variant silently did nothing — a two-tap guard that was not there.
    // That is now load-bearing rather than theoretical: the cancel-alert
    // button had to leave the danger variant to stay visible on the red
    // emergency field, and under the old gate it would have quietly lost its
    // confirmation step.
    if (widget.confirmRequired && !_armed) {
      _armTimer?.cancel();
      setState(() => _armed = true);
      _armTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    _armTimer?.cancel();
    setState(() => _armed = false);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut, reverseCurve: Curves.elasticOut),
    );

    final colors = _resolveColors(context, widget.variant);
    final label = _armed ? 'Tap again to confirm' : widget.label;

    return Semantics(
      label: widget.semanticsLabel ?? label,
      button: true,
      enabled: !_disabled,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapCancel: _onTapCancel,
        onTapUp: _onTapUp,
        onTap: _handleTap,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: scale,
            builder: (context, child) => Transform.scale(scale: scale.value, child: child),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _disabled && !widget.isLoading ? 0.4 : 1.0,
              child: Container(
                height: widget.size.height,
                width: widget.fullWidth ? double.infinity : null,
                padding: EdgeInsets.symmetric(horizontal: widget.size.horizontalPadding),
                constraints: const BoxConstraints(minWidth: AppSpacing.minTouchTarget),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: AppRadius.mdRadius,
                  border: colors.border != null ? Border.all(color: colors.border!, width: 1.5) : null,
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: widget.isLoading
                      ? SizedBox(
                          key: const ValueKey('loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.foreground),
                        )
                      : Row(
                          key: const ValueKey('label'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              IconTheme(
                                data: IconThemeData(color: colors.foreground, size: 18),
                                child: widget.icon!,
                              ),
                              const SizedBox(width: AppSpacing.space2),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: widget.size.labelStyle.copyWith(color: colors.foreground),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _SaButtonColors _resolveColors(BuildContext context, SaButtonVariant variant) {
    final saColors = context.saColors;
    return switch (variant) {
      SaButtonVariant.primary => _SaButtonColors(
        background: Theme.of(context).colorScheme.primary,
        foreground: Theme.of(context).colorScheme.onPrimary,
      ),
      SaButtonVariant.secondary => _SaButtonColors(
        background: saColors.surfaceHighest,
        foreground: Theme.of(context).colorScheme.onSurface,
      ),
      SaButtonVariant.ghost => _SaButtonColors(
        background: Colors.transparent,
        foreground: saColors.interactive,
        border: saColors.interactive,
      ),
      SaButtonVariant.danger => _SaButtonColors(
        background: _armed ? AppColors.coral600 : AppColors.coral500,
        foreground: Colors.white,
      ),
      // The two treatments that work on `AppColors.emergencyField`. Nothing
      // tinted survives on that ground — coral on oxide red is barely a
      // colour change — so the contrast has to come from the paper.
      SaButtonVariant.inverse => _SaButtonColors(
        background: _armed ? AppColors.neutral300 : AppColors.neutral50,
        foreground: AppColors.emergencyField,
      ),
      SaButtonVariant.inverseOutline => _SaButtonColors(
        background: _armed
            ? AppColors.neutral50.withValues(alpha: 0.22)
            : Colors.transparent,
        foreground: AppColors.neutral50,
        border: AppColors.neutral50.withValues(alpha: 0.55),
      ),
    };
  }
}

class _SaButtonColors {
  _SaButtonColors({this.background, required this.foreground, this.border});

  final Color? background;
  final Color foreground;
  final Color? border;
}
