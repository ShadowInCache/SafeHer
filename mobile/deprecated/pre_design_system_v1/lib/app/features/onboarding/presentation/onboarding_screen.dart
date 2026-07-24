import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/premium_theme.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/state/providers.dart';

class OnboardingFlowScreen extends ConsumerStatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  ConsumerState<OnboardingFlowScreen> createState() =>
      _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends ConsumerState<OnboardingFlowScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _pages = [
    (
      title: 'Connected Wearable Protection',
      description:
          'Link your Smart Glove and Smart Glasses for continuous AI-powered protection and live diagnostics.',
      icon: Icons.watch,
    ),
    (
      title: 'AI Threat Intelligence',
      description:
          'Motion anomalies, voice aggression, weapon cues, and contextual risk scoring are fused in real-time.',
      icon: Icons.psychology_alt,
    ),
    (
      title: 'Instant SOS + Evidence',
      description:
          'Automatically notify guardians and responders with location, encrypted evidence, and AI summaries.',
      icon: Icons.sos,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: PremiumTheme.heroGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: TextButton(
                    onPressed: _complete,
                    child: const Text('Skip'),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, pageIndex) {
                      final page = _pages[pageIndex];
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GlassCard(
                            padding: const EdgeInsets.all(26),
                            tint: Colors.white,
                            child: Column(
                              children: [
                                Icon(
                                  page.icon,
                                  size: 72,
                                  color: PremiumTheme.accent,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  page.title,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  page.description,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (dotIndex) {
                    final active = dotIndex == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? PremiumTheme.accent : Colors.white38,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _index == _pages.length - 1 ? _complete : _next,
                  child: Text(
                    _index == _pages.length - 1 ? 'Get Started' : 'Next',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _complete() async {
    await ref.read(sessionControllerProvider.notifier).completeOnboarding();
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.privacyConsent);
    }
  }
}
