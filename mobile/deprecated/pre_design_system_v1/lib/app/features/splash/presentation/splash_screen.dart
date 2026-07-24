import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/premium_theme.dart';
import '../../../shared/state/providers.dart';
import '../../../shared/state/session_controller.dart';

class SafeHerSplashScreen extends ConsumerStatefulWidget {
  const SafeHerSplashScreen({super.key});

  @override
  ConsumerState<SafeHerSplashScreen> createState() =>
      _SafeHerSplashScreenState();
}

class _SafeHerSplashScreenState extends ConsumerState<SafeHerSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _startRouting();
  }

  Future<void> _startRouting() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) {
      return;
    }

    var session = ref.read(sessionControllerProvider);
    while (session.initializing) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) {
        return;
      }
      session = ref.read(sessionControllerProvider);
    }

    final route = _resolveRoute(session);
    if (!mounted) {
      return;
    }

    Navigator.pushReplacementNamed(context, route);
  }

  String _resolveRoute(SessionState session) {
    if (!session.onboardingComplete) {
      return AppRoutes.onboarding;
    }
    if (!session.consentAccepted) {
      return AppRoutes.privacyConsent;
    }
    if (!session.permissionsSetupComplete) {
      return AppRoutes.permissionsSetup;
    }
    if (!session.authenticated) {
      return AppRoutes.login;
    }
    return AppRoutes.home;
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: PremiumTheme.heroGradient),
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            ),
            child: ScaleTransition(
              scale: CurvedAnimation(
                parent: _animationController,
                curve: Curves.easeOutBack,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0EA5E9), Color(0xFFF97316)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      size: 62,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'SafeHer',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineLarge?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'AI-powered wearable safety ecosystem',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.84),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator.adaptive(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
