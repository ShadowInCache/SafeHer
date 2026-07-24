import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';

/// Central route table. Routes are added incrementally as each screen in
/// the build sequence lands — see the spec's ROUTE TABLE for the full,
/// eventual set.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', name: 'splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/onboarding', name: 'onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/auth/login', name: 'login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/auth/signup', name: 'signup', builder: (context, state) => const SignupScreen()),
      GoRoute(path: '/auth/otp', name: 'otp', builder: (context, state) => const OtpScreen()),
      GoRoute(path: '/auth/forgot', name: 'forgot', builder: (context, state) => const ForgotPasswordScreen()),
    ],
  );
});
