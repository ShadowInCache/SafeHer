import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_routes.dart';
import 'core/localization/app_localizations.dart';
import 'core/theme/premium_theme.dart';
import 'features/dashboard/presentation/home_dashboard_screen.dart';
import 'features/incidents/presentation/incident_history_screen.dart';
import 'features/map/presentation/live_tracking_map_screen.dart';
import 'features/monitoring/presentation/threat_monitoring_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'shared/models/domain_models.dart';
import 'shared/state/providers.dart';
import 'shared/widgets/offline_banner.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _index = 0;
  ProviderSubscription<AsyncValue<bool>>? _connectivitySub;

  static const _tabTitles = [
    'Dashboard',
    'Threat Monitoring',
    'Live Tracking',
    'Incidents',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _connectivitySub = ref.listenManual<AsyncValue<bool>>(
      connectivityProvider,
      (previous, next) {
        next.whenData((online) {
          ref.read(safetyControllerProvider.notifier).setOfflineMode(!online);
        });
      },
    );
  }

  @override
  void dispose() {
    _connectivitySub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final safety = ref.watch(safetyControllerProvider);

    final tabs = const [
      HomeDashboardScreen(),
      ThreatMonitoringScreenV2(),
      LiveTrackingMapScreenV2(),
      IncidentHistoryScreenV2(),
      SettingsScreenV2(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitles[_index]),
        actions: [
          if (safety.threatLevel == ThreatLevelState.danger)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                backgroundColor: PremiumTheme.danger,
                label: const Text(
                  'DANGER',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.notifications),
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(session.user?.fullName ?? 'SafeHer User'),
                accountEmail: Text(session.user?.email ?? ''),
                currentAccountPicture: const CircleAvatar(
                  child: Icon(Icons.person),
                ),
              ),
              _DrawerLink(
                icon: Icons.watch_outlined,
                label: context.l10n.t('devicePairing'),
                route: AppRoutes.devicePairing,
              ),
              _DrawerLink(
                icon: Icons.contact_phone_outlined,
                label: context.l10n.t('contacts'),
                route: AppRoutes.emergencyContacts,
              ),
              _DrawerLink(
                icon: Icons.analytics_outlined,
                label: context.l10n.t('analytics'),
                route: AppRoutes.analyticsDashboard,
              ),
              _DrawerLink(
                icon: Icons.group_outlined,
                label: 'Guardian Tracking',
                route: AppRoutes.guardianTracking,
              ),
              _DrawerLink(
                icon: Icons.person_outline,
                label: context.l10n.t('profile'),
                route: AppRoutes.profile,
              ),
              _DrawerLink(
                icon: Icons.privacy_tip_outlined,
                label: context.l10n.t('privacyConsent'),
                route: AppRoutes.privacyConsent,
              ),
              _DrawerLink(
                icon: Icons.security_outlined,
                label: context.l10n.t('permissionsSetup'),
                route: AppRoutes.permissionsSetup,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(context.l10n.t('logout')),
                onTap: () async {
                  await ref.read(sessionControllerProvider.notifier).logout();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRoutes.login,
                    (_) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          OfflineBanner(offline: safety.offlineMode),
          Expanded(
            child: IndexedStack(index: _index, children: tabs),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.sos),
        backgroundColor: PremiumTheme.danger,
        icon: const Icon(Icons.sos, color: Colors.white),
        label: const Text(
          'SOS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            label: 'Monitor',
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Incidents',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;

  const _DrawerLink({
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushNamed(context, route);
      },
    );
  }
}
