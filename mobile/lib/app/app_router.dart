import 'package:flutter/material.dart';

import 'core/constants/app_routes.dart';
import 'features/analytics/presentation/analytics_dashboard_screen.dart';
import 'features/auth/presentation/forgot_password_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/otp_verification_screen.dart';
import 'features/auth/presentation/signup_screen.dart';
import 'features/consent/presentation/privacy_consent_screen.dart';
import 'features/contacts/presentation/emergency_contacts_screen.dart';
import 'features/devices/presentation/device_pairing_screen.dart';
import 'features/guardian/presentation/guardian_tracking_screen.dart';
import 'features/incidents/presentation/incident_details_screen.dart';
import 'features/incidents/presentation/incident_history_screen.dart';
import 'features/map/presentation/live_tracking_map_screen.dart';
import 'features/monitoring/presentation/threat_monitoring_screen.dart';
import 'features/notifications/presentation/notifications_screen.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'features/permissions/presentation/permissions_setup_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/sos/presentation/sos_screen.dart';
import 'features/splash/presentation/splash_screen.dart';
import 'main_shell_screen.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.root:
        return _page(const SafeHerSplashScreen(), settings);
      case AppRoutes.splash:
        return _page(const SafeHerSplashScreen(), settings);
      case AppRoutes.onboarding:
        return _page(const OnboardingFlowScreen(), settings);
      case AppRoutes.login:
        return _page(const AuthLoginScreen(), settings);
      case AppRoutes.signup:
        return _page(const AuthSignupScreen(), settings);
      case AppRoutes.otpVerification:
        return _page(const OtpVerificationScreen(), settings);
      case AppRoutes.forgotPassword:
        return _page(const ForgotPasswordScreen(), settings);
      case AppRoutes.privacyConsent:
        return _page(const PrivacyConsentScreen(), settings);
      case AppRoutes.permissionsSetup:
        return _page(const PermissionsSetupScreen(), settings);
      case AppRoutes.home:
        return _page(const MainShellScreen(), settings);
      case AppRoutes.devicePairing:
        return _page(const DevicePairingFeatureScreen(), settings);
      case AppRoutes.threatMonitoring:
        return _page(const ThreatMonitoringScreenV2(), settings);
      case AppRoutes.liveTrackingMap:
        return _page(const LiveTrackingMapScreenV2(), settings);
      case AppRoutes.sos:
        return _page(const SosActivationScreen(), settings);
      case AppRoutes.incidentHistory:
        return _page(const IncidentHistoryScreenV2(), settings);
      case AppRoutes.incidentDetails:
        return _page(const IncidentDetailsScreenV2(), settings);
      case AppRoutes.emergencyContacts:
        return _page(const EmergencyContactsScreenV2(), settings);
      case AppRoutes.analyticsDashboard:
        return _page(const AnalyticsDashboardScreen(), settings);
      case AppRoutes.notifications:
        return _page(const NotificationsCenterScreen(), settings);
      case AppRoutes.guardianTracking:
        return _page(const GuardianTrackingScreenV2(), settings);
      case AppRoutes.profile:
        return _page(const ProfileScreenV2(), settings);
      case AppRoutes.settings:
        return _page(const SettingsScreenV2(), settings);
      default:
        return _page(
          const Scaffold(body: Center(child: Text('Route not found.'))),
          settings,
        );
    }
  }

  static PageRoute<dynamic> _page(Widget child, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slide =
            Tween<Offset>(
              begin: const Offset(0.02, 0.02),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }
}
