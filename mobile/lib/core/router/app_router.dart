import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/devices/presentation/device_management_screen.dart';
import '../../features/emergency/presentation/emergency_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/monitoring/presentation/live_monitoring_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/reports/presentation/report_detail_screen.dart';
import '../../features/reports/presentation/reports_list_screen.dart';
import '../../features/search/presentation/search_screen.dart';

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
      GoRoute(path: '/home', name: 'home', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/devices',
        name: 'devices',
        builder: (context, state) => const DeviceManagementScreen(),
      ),
      GoRoute(
        path: '/devices/:id',
        name: 'device-detail',
        builder: (context, state) => DeviceManagementScreen(initialExpandedId: state.pathParameters['id']),
      ),
      GoRoute(path: '/monitor', name: 'monitor', builder: (context, state) => const LiveMonitoringScreen()),
      GoRoute(path: '/dashboard', name: 'dashboard', builder: (context, state) => const DashboardScreen()),
      GoRoute(path: '/search', name: 'search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/emergency', name: 'emergency', builder: (context, state) => const EmergencyScreen()),
      GoRoute(path: '/reports', name: 'reports', builder: (context, state) => const ReportsListScreen()),
      GoRoute(
        path: '/reports/:id',
        name: 'report-detail',
        builder: (context, state) => ReportDetailScreen(reportId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/profile', name: 'profile', builder: (context, state) => const ProfileScreen()),
    ],
  );
});
