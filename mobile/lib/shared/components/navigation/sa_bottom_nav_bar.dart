import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';
import '../icons/sa_icon.dart';

/// The four primary destinations, per SRS Part 3 §"Component Spec:
/// SaBottomNavBar" — Home / Monitor / Dashboard / Profile.
///
/// Home is the live command centre (safety status, devices, quick actions);
/// Dashboard is the retrospective analytics view (`/dashboard`, SCREEN 9).
/// They answer different questions — "am I safe right now" versus "what has
/// been happening to me" — which is why the SRS gives each its own tab.
///
/// Device management is deliberately not a tab: it's a management task, not
/// a place you dwell, and it stays one tap away from Home, Profile and
/// Search.
enum SaNavTab { home, monitor, dashboard, profile }

extension on SaNavTab {
  SaIconGlyph get glyph => switch (this) {
    SaNavTab.home => SaIconGlyph.home,
    SaNavTab.monitor => SaIconGlyph.monitorPulse,
    SaNavTab.dashboard => SaIconGlyph.dashboard,
    SaNavTab.profile => SaIconGlyph.profile,
  };

  String get label => switch (this) {
    SaNavTab.home => 'Home',
    SaNavTab.monitor => 'Monitor',
    SaNavTab.dashboard => 'Dashboard',
    SaNavTab.profile => 'Profile',
  };
}

/// Floating pill bottom navigation with a center SOS FAB. The FAB is not a
/// tab — [onSosTap] is a separate callback (typically a Hero morph into the
/// Emergency screen).
///
/// [visible] drives the scroll-aware hide/show translateY; callers with
/// scrollable content should wrap it in a scroll listener and flip this
/// (screens that must always show the bar — Home, Emergency, Profile —
/// simply never flip it to false).
class SaBottomNavBar extends StatelessWidget {
  const SaBottomNavBar({
    required this.currentTab,
    required this.onTabSelected,
    required this.onSosTap,
    super.key,
    this.visible = true,
  });

  /// Null on screens that are reachable from the bar but are not themselves
  /// destinations (Device Management, for one) — the bar still shows, with
  /// no tab claiming to be current.
  final SaNavTab? currentTab;
  final ValueChanged<SaNavTab> onTabSelected;
  final VoidCallback onSosTap;
  final bool visible;

  static const _leftTabs = [SaNavTab.home, SaNavTab.monitor];
  static const _rightTabs = [SaNavTab.dashboard, SaNavTab.profile];

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AnimationHelpers.reducedMotion(context);
    return AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      offset: visible || reducedMotion ? Offset.zero : const Offset(0, 1.3),
      child: SizedBox(
        // Tall enough to contain the pill (64) + gap (12) + FAB (56) without
        // the FAB overflowing above the Stack's bounds — negative-position
        // Positioned overflow (even with clipBehavior: Clip.none) produced
        // a hit-testable area that didn't match the FAB's visual/layout
        // position in testing, which would mean part of the real button
        // wasn't tappable on-device either.
        height: 132,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: AppRadius.fullRadius,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.dark800.withValues(alpha: 0.3),
                      borderRadius: AppRadius.fullRadius,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final tab in _leftTabs)
                                _NavTabItem(tab: tab, isActive: tab == currentTab, onTap: () => _select(tab)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 64),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              for (final tab in _rightTabs)
                                _NavTabItem(tab: tab, isActive: tab == currentTab, onTap: () => _select(tab)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 76,
              child: _SosFab(onTap: onSosTap),
            ),
          ],
        ),
      ),
    );
  }

  void _select(SaNavTab tab) {
    if (tab != currentTab) HapticFeedback.selectionClick();
    onTabSelected(tab);
  }
}

class _NavTabItem extends StatelessWidget {
  const _NavTabItem({required this.tab, required this.isActive, required this.onTap});

  final SaNavTab tab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tab.label,
      selected: isActive,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 56,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isActive ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: isActive ? 1.0 : 0.5,
                  duration: const Duration(milliseconds: 200),
                  child: SaIcon(tab.glyph, size: 24, color: Colors.white),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isActive
                    ? Text(
                        tab.label,
                        key: ValueKey(tab),
                        style: AppTypography.labelM.copyWith(color: Colors.white),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox(height: 14, key: ValueKey('empty')),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(top: 2),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? AppColors.violet500 : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosFab extends StatefulWidget {
  const _SosFab({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SosFab> createState() => _SosFabState();
}

class _SosFabState extends State<_SosFab> with SingleTickerProviderStateMixin {
  late final AnimationController _breatheController;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AnimationHelpers.repeat(context, _breatheController, reverse: true);
    });
  }

  @override
  void dispose() {
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breathe = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOut),
    );
    return Semantics(
      label: 'SOS emergency',
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Hero(
          tag: 'sos_fab',
          child: AnimatedBuilder(
            animation: breathe,
            builder: (context, child) => Transform.scale(scale: breathe.value, child: child),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.coral500,
                boxShadow: [BoxShadow(color: AppColors.coral500.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 2)],
              ),
              alignment: Alignment.center,
              child: const SaIcon(SaIconGlyph.shield, size: 26, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
