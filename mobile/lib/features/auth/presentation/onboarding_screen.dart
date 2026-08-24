import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/local/onboarding_prefs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';

/// One page of the introduction.
///
/// [ground] and [ink] are carried per page rather than read from the theme
/// because the sequence *is* the point: see [OnboardingScreen].
class _OnboardingPage {
  const _OnboardingPage({
    required this.title,
    required this.body,
    required this.ground,
    required this.ink,
    required this.inkMuted,
    required this.mark,
  });

  final String title;
  final String body;
  final Color ground;
  final Color ink;
  final Color inkMuted;
  final _MarkKind mark;
}

enum _MarkKind { watch, sense, alert }

/// 3-page introduction.
///
/// **The sequence teaches the app's colour language.** SafeHer's premise is
/// "calm by default, unmistakable in emergency" -- warm stone while
/// everything is fine, an oxide-red field the moment an alert is out. The
/// onboarding now walks through exactly that: stone, then ink, then the
/// emergency field itself. The third page is not a page *about* the alert
/// screen; it is the same red the dispatched screen paints, so the first time
/// a user triggers an SOS she has already seen what it looks like.
///
/// The ground lerps continuously with the swipe, so the change is something
/// you feel rather than three unrelated backdrops. Ink, marks, indicator and
/// buttons all take their colour from the blended pair, which is why none of
/// them can be const.
///
/// This replaced three radial violet/indigo/coral gradients behind centred
/// white text, which looked like every other onboarding and said nothing
/// about this app in particular.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  static const _paperMuted = Color(0xB3FAF8F4); // paper at 70%

  late final List<_OnboardingPage> _pages = [
    const _OnboardingPage(
      title: 'Always Protected',
      body: 'SafeHer watches over you silently, every step of the way.',
      ground: AppColors.light50,
      ink: AppColors.neutral900,
      inkMuted: AppColors.neutral500,
      mark: _MarkKind.watch,
    ),
    const _OnboardingPage(
      title: 'AI That Understands',
      body: 'Motion, sound, and vision working together to keep you safe.',
      ground: AppColors.dark900,
      ink: AppColors.neutral100,
      inkMuted: AppColors.neutral400,
      mark: _MarkKind.sense,
    ),
    const _OnboardingPage(
      title: 'Help in Seconds',
      body: 'One tap. Your trusted people know exactly where you are.',
      ground: AppColors.emergencyField,
      ink: AppColors.neutral50,
      inkMuted: _paperMuted,
      mark: _MarkKind.alert,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _page) _page = page;
      // The ground follows the swipe continuously, so every frame of a drag
      // needs a repaint, not only the ones that cross a page boundary.
      setState(() {});
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
    final lower = _pages[fraction.floor().clamp(0, _pages.length - 1)];
    final upper = _pages[fraction.ceil().clamp(0, _pages.length - 1)];
    final t = fraction - fraction.floor();

    final ground = Color.lerp(lower.ground, upper.ground, t)!;
    final ink = Color.lerp(lower.ink, upper.ink, t)!;
    final inkMuted = Color.lerp(lower.inkMuted, upper.inkMuted, t)!;
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: ground,
      body: SafeArea(
        child: Stack(
          children: [
            // Flutter's default dragDevices leave the mouse out on web and
            // desktop, so in Chrome this PageView could not be advanced at
            // all -- the only way past page one was Skip, which also ends the
            // introduction. Anyone demoing or testing in a browser saw
            // exactly one page and assumed that was all there was.
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final parallax = _pageController.hasClients && _pageController.page != null
                      ? (_pageController.page! - index)
                      : 0.0;
                  return _OnboardingPageView(
                    page: _pages[index],
                    index: index,
                    total: _pages.length,
                    ink: ink,
                    inkMuted: inkMuted,
                    parallax: parallax,
                  );
                },
              ),
            ),
            if (!isLast)
              Positioned(
                top: AppSpacing.space2,
                right: AppSpacing.space4,
                child: Semantics(
                  button: true,
                  label: 'Skip',
                  child: GestureDetector(
                    onTap: _complete,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      // Keeps a 44dp target around a small label.
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      child: Text(
                        'Skip',
                        style: AppTypography.labelL.copyWith(color: inkMuted),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: AppSpacing.screenMarginPhone,
              right: AppSpacing.screenMarginPhone,
              bottom: AppSpacing.space8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLast) ...[
                    SaButton(
                      label: 'Get Started',
                      size: SaButtonSize.lg,
                      fullWidth: true,
                      // Paper on the emergency field. The primary variant is
                      // aubergine, which on this red reads as a bruise.
                      variant: SaButtonVariant.inverse,
                      onPressed: _complete,
                    ),
                    const SizedBox(height: AppSpacing.space6),
                  ],
                  _PageIndicator(count: _pages.length, current: _page, ink: ink),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({
    required this.page,
    required this.index,
    required this.total,
    required this.ink,
    required this.inkMuted,
    required this.parallax,
  });

  final _OnboardingPage page;
  final int index;
  final int total;
  final Color ink;
  final Color inkMuted;
  final double parallax;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The mark drifts at a different rate to the copy, so the two read
          // as separate planes rather than one sliding card.
          Transform.translate(
            offset: Offset(parallax * -56, 0),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: CustomPaint(painter: _MarkPainter(kind: page.mark, ink: ink)),
            ),
          ),
          const SizedBox(height: AppSpacing.space10),
          Container(height: 1, color: ink.withValues(alpha: 0.25)),
          const SizedBox(height: AppSpacing.space3),
          // A real sequence, so a numbered eyebrow states something true --
          // how far through you are -- rather than decorating.
          Text(
            '${(index + 1).toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}',
            style: AppTypography.eyebrow.copyWith(color: inkMuted),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            page.title,
            style: AppTypography.displayCondensed.copyWith(color: ink, fontSize: 46),
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            page.body,
            style: AppTypography.bodyL.copyWith(color: inkMuted),
          ),
          const SizedBox(height: AppSpacing.space16),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.count, required this.current, required this.ink});

  final int count;
  final int current;
  final Color ink;

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
            width: active ? 28 : 8,
            height: 2,
            decoration: BoxDecoration(
              color: ink.withValues(alpha: active ? 1 : 0.3),
              borderRadius: AppRadius.fullRadius,
            ),
          );
        }),
      ),
    );
  }
}

/// The three marks, drawn in one stroke language: hairline geometry, a single
/// heavier accent, fills only where the meaning needs weight.
///
/// They are drawn rather than composed from the shield glyph because each has
/// something specific to say -- a quiet sweep, three senses converging, an
/// alert leaving -- and a scaled-up shield says only "security app".
class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.kind, required this.ink});

  final _MarkKind kind;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.34, size.height / 2);
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ink.withValues(alpha: 0.30);
    final solid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = ink;

    switch (kind) {
      case _MarkKind.watch:
        // Concentric rings at rest: watching, not scanning.
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(c, 22.0 * i, hair);
        }
        canvas.drawCircle(c, 22, Paint()..color = ink.withValues(alpha: 0.10));
        canvas.drawArc(Rect.fromCircle(center: c, radius: 44), -2.2, 1.5, false, solid);
        canvas.drawCircle(c, 4, Paint()..color = ink);

      case _MarkKind.sense:
        // Three senses -- motion, sound, vision -- converging on one point.
        const r = 76.0;
        for (var i = 0; i < 3; i++) {
          final a = -math.pi / 2 + i * (2 * math.pi / 3);
          final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
          canvas.drawLine(c, p, hair);
          canvas.drawCircle(p, 13, hair);
          canvas.drawCircle(p, 4, Paint()..color = ink);
        }
        canvas.drawCircle(c, 26, hair);
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: 26),
          -math.pi / 2,
          math.pi * 1.35,
          false,
          solid,
        );

      case _MarkKind.alert:
        // The alert leaving: a solid centre, rings thinning as they travel.
        for (var i = 1; i <= 4; i++) {
          canvas.drawCircle(
            c,
            20.0 * i + 6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = i == 1 ? 2 : 1
              ..color = ink.withValues(alpha: 0.55 / i),
          );
        }
        canvas.drawCircle(c, 13, Paint()..color = ink);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.kind != kind || old.ink != ink;
}
