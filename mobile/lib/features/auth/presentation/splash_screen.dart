import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/animation_helpers.dart';
import '../../../core/local/onboarding_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../data/auth_providers.dart';

/// Splash: ≤1.8s brand animation while the onboarding flag + auth session
/// are checked in the background, then a single redirect. No spinner is
/// ever shown — the animation itself is the loading state.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  static const _totalDuration = Duration(milliseconds: 1800);

  late final AnimationController _controller;
  late Future<bool> _hasActiveSession;

  @override
  void initState() {
    super.initState();
    _hasActiveSession = ref.read(authRepositoryProvider).hasActiveSession();
    _controller = AnimationController(vsync: this, duration: _totalDuration);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final reducedMotion = AnimationHelpers.reducedMotion(context);
    final animationDone = reducedMotion
        ? Future<void>.value()
        : AnimationHelpers.forward(context, _controller);
    if (reducedMotion) _controller.value = 1;

    final results = await Future.wait([animationDone, _hasActiveSession]);
    if (!mounted) return;

    final hasActiveSession = results[1] as bool;
    final prefs = ref.read(onboardingPrefsProvider);
    final destination = !prefs.hasSeenOnboarding
        ? '/onboarding'
        : (hasActiveSession ? '/home' : '/auth/login');

    // ignore: use_build_context_synchronously
    context.go(destination);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _intervalValue(double start, double end) {
    if (_controller.value <= start) return 0;
    if (_controller.value >= end) return 1;
    return (_controller.value - start) / (end - start);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark900,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final shieldIn = Curves.easeOut.transform(_intervalValue(0, 300 / 1800));
          final lockPulse = Curves.easeOut.transform(_intervalValue(300 / 1800, 700 / 1800));
          final wordmarkIn = Curves.easeOut.transform(_intervalValue(700 / 1800, 1100 / 1800));
          final taglineIn = Curves.easeOut.transform(_intervalValue(900 / 1800, 1100 / 1800));
          final glowPulse = Curves.easeOut.transform(_intervalValue(1100 / 1800, 1500 / 1800));
          final finalFade = 1 - _intervalValue(1500 / 1800, 1800 / 1800);

          final glowDiameter = shieldIn < 1
              ? 80 * shieldIn
              : 80 + 40 * glowPulse;
          final glowOpacity = shieldIn < 1 ? 0.4 * shieldIn : 0.4 * (1 - glowPulse);
          final shieldScale = 0.6 + 0.4 * shieldIn + 0.06 * lockPulse * (1 - lockPulse) * 4;

          return Opacity(
            opacity: finalFade,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: glowDiameter,
                          height: glowDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.violet500.withValues(alpha: glowOpacity),
                            boxShadow: [
                              BoxShadow(color: AppColors.violet500.withValues(alpha: glowOpacity * 0.6), blurRadius: 24),
                            ],
                          ),
                        ),
                        Opacity(
                          opacity: shieldIn,
                          child: Transform.scale(
                            scale: shieldScale,
                            child: const SaIcon(SaIconGlyph.shield, size: 64, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Opacity(
                    opacity: wordmarkIn,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - wordmarkIn)),
                      child: Text(
                        'SAFEHER',
                        style: AppTypography.displayM.copyWith(color: Colors.white, letterSpacing: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: taglineIn,
                    child: Text(
                      'Always protected.',
                      style: AppTypography.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
