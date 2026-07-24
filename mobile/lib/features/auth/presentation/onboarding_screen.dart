import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/local/onboarding_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/icons/sa_icon.dart';

class _OnboardingPage {
  const _OnboardingPage({
    required this.title,
    required this.body,
    required this.gradientTop,
    required this.illustration,
  });

  final String title;
  final String body;
  final Color gradientTop;
  final Widget illustration;
}

/// 3-page introduction. No design assets (Rive/Lottie) were supplied, so
/// each page's illustration is an abstract composition built from existing
/// glyphs/gradients rather than a literal character animation.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  late final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      title: 'Always Protected',
      body: 'SafeHer watches over you silently, every step of the way.',
      gradientTop: AppColors.violet950,
      illustration: const _ShieldAuraIllustration(),
    ),
    _OnboardingPage(
      title: 'AI That Understands',
      body: 'Motion, sound, and vision working together to keep you safe.',
      gradientTop: AppColors.indigo900,
      illustration: const _NeuralShieldIllustration(),
    ),
    _OnboardingPage(
      title: 'Help in Seconds',
      body: 'One tap. Your trusted people know exactly where you are.',
      gradientTop: AppColors.coral900,
      illustration: const _SosRippleIllustration(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _page) setState(() => _page = page);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    await ref.read(onboardingPrefsProvider).setSeenOnboarding();
    if (!mounted) return;
    context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final fraction = _pageController.hasClients && _pageController.page != null
        ? _pageController.page!
        : _page.toDouble();
    final currentGradient = _pages[fraction.floor().clamp(0, _pages.length - 1)].gradientTop;
    final nextGradient = _pages[fraction.ceil().clamp(0, _pages.length - 1)].gradientTop;
    final blendedTop = Color.lerp(currentGradient, nextGradient, fraction - fraction.floor())!;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [blendedTop, AppColors.dark900],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final parallax = _pageController.hasClients && _pageController.page != null
                      ? (_pageController.page! - index) * 0.3
                      : 0.0;
                  return _OnboardingPageView(
                    page: _pages[index],
                    isLast: index == _pages.length - 1,
                    parallaxOffset: parallax,
                    onGetStarted: _complete,
                  );
                },
              ),
              if (_page < _pages.length - 1)
                Positioned(
                  top: AppSpacing.space4,
                  right: AppSpacing.space5,
                  child: SaButton(
                    label: 'Skip',
                    variant: SaButtonVariant.ghost,
                    size: SaButtonSize.sm,
                    onPressed: _complete,
                  ),
                ),
              Positioned(
                bottom: AppSpacing.space10,
                left: 0,
                right: 0,
                child: Center(child: _PageIndicator(count: _pages.length, current: _page)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({
    required this.page,
    required this.isLast,
    required this.parallaxOffset,
    required this.onGetStarted,
  });

  final _OnboardingPage page;
  final bool isLast;
  final double parallaxOffset;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: Offset(parallaxOffset * -40, 0),
            child: SizedBox(height: 220, child: page.illustration),
          ),
          const SizedBox(height: AppSpacing.space10),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppTypography.displayXL.copyWith(color: AppColors.violet600, fontSize: 34),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: AppTypography.bodyL.copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
          if (isLast) ...[
            const SizedBox(height: AppSpacing.space8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 20, end: 0),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, offsetY, child) => Transform.translate(offset: Offset(0, offsetY), child: child),
              child: SaButton(
                label: 'Get Started',
                size: SaButtonSize.lg,
                fullWidth: true,
                onPressed: onGetStarted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space16),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (i) {
          final active = i == current;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withValues(alpha: 0.35),
              borderRadius: AppRadius.fullRadius,
            ),
          );
        }),
      ),
    );
  }
}

class _ShieldAuraIllustration extends StatelessWidget {
  const _ShieldAuraIllustration();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [AppColors.violet500.withValues(alpha: 0.35), Colors.transparent]),
            ),
          ),
          const SaIcon(SaIconGlyph.shield, size: 96, color: Colors.white, strokeWidth: 2.5),
        ],
      ),
    );
  }
}

class _NeuralShieldIllustration extends StatelessWidget {
  const _NeuralShieldIllustration();

  static const _nodeOffsets = [
    Offset(-70, -50),
    Offset(70, -50),
    Offset(-90, 20),
    Offset(90, 20),
    Offset(0, -80),
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 220,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: const Size(220, 200), painter: _NeuralLinesPainter(_nodeOffsets)),
            for (final offset in _nodeOffsets)
              Transform.translate(
                offset: offset,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.violet500),
                ),
              ),
            const SaIcon(SaIconGlyph.shield, size: 72, color: Colors.white, strokeWidth: 2.5),
          ],
        ),
      ),
    );
  }
}

class _NeuralLinesPainter extends CustomPainter {
  _NeuralLinesPainter(this.nodes);

  final List<Offset> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = AppColors.violet500.withValues(alpha: 0.4)
      ..strokeWidth = 1.5;
    for (final node in nodes) {
      canvas.drawLine(center, center + node, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralLinesPainter oldDelegate) => false;
}

class _SosRippleIllustration extends StatefulWidget {
  const _SosRippleIllustration();

  @override
  State<_SosRippleIllustration> createState() => _SosRippleIllustrationState();
}

class _SosRippleIllustrationState extends State<_SosRippleIllustration> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static const _contactOffsets = [Offset(-90, -20), Offset(90, -20), Offset(-70, 60), Offset(70, 60)];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 220,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(size: const Size(220, 200), painter: _RipplePainter(_controller.value));
              },
            ),
            for (final offset in _contactOffsets)
              Transform.translate(
                offset: offset,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.dark700),
                  child: const SaIcon(SaIconGlyph.profile, size: 16, color: Colors.white),
                ),
              ),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.coral500),
              child: const SaIcon(SaIconGlyph.shield, size: 32, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = 32 + t * 70;
      final paint = Paint()
        ..color = AppColors.coral500.withValues(alpha: (1 - t) * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) => oldDelegate.progress != progress;
}
