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
///
/// The mark used to sit in a violet glow that pulsed and faded. This builds
/// the identity out of the same three devices the rest of the app uses: a
/// stroked mark, a hairline rule, and a mono eyebrow. The rule draws outward
/// from the centre — it is the same line that opens every section inside the
/// app, so the first thing the user sees is the app's own grammar.
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
          // Same interval boundaries as before, so the screen still occupies
          // exactly its 1.8s budget and the redirect is unchanged.
          final markIn = Curves.easeOut.transform(_intervalValue(0, 300 / 1800));
          final ringIn = Curves.easeOut.transform(_intervalValue(300 / 1800, 700 / 1800));
          final wordmarkIn = Curves.easeOut.transform(_intervalValue(700 / 1800, 1100 / 1800));
          final ruleIn = Curves.easeOutCubic.transform(_intervalValue(900 / 1800, 1400 / 1800));
          final taglineIn = Curves.easeOut.transform(_intervalValue(1100 / 1800, 1500 / 1800));
          final finalFade = 1 - _intervalValue(1500 / 1800, 1800 / 1800);

          return Opacity(
            opacity: finalFade,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: CustomPaint(
                      painter: _MarkPainter(markIn: markIn, ringIn: ringIn),
                      child: Center(
                        child: Opacity(
                          opacity: markIn,
                          child: Transform.scale(
                            scale: 0.82 + 0.18 * markIn,
                            child: const SaIcon(
                              SaIconGlyph.shield,
                              size: 56,
                              color: AppColors.neutral50,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Opacity(
                    opacity: wordmarkIn,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - wordmarkIn)),
                      child: Text(
                        'SAFEHER',
                        style: AppTypography.displayCondensed.copyWith(
                          color: AppColors.neutral50,
                          fontSize: 46,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // The rule draws outward from the centre rather than fading
                  // in, so the identity assembles itself instead of appearing.
                  SizedBox(
                    height: 1,
                    width: 200 * ruleIn,
                    child: const ColoredBox(color: AppColors.dark600),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: taglineIn,
                    child: Text(
                      'ALWAYS PROTECTED',
                      style: AppTypography.eyebrow.copyWith(color: AppColors.neutral400),
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

/// The ring behind the mark: a full circle in the night line colour, with an
/// oxide-red arc sweeping over it. Red because this is a safety app and the
/// arc is the one place on the splash that says so — everything else is ink.
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.markIn, required this.ringIn});

  final double markIn;
  final double ringIn;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.dark600.withValues(alpha: markIn),
    );

    if (ringIn <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // 12 o'clock
      6.2832 * ringIn,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = AppColors.coral400,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.markIn != markIn || old.ringIn != ringIn;
}
