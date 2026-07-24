import 'package:flutter/material.dart';
import 'dart:ui';
import '../dashboard/enhanced_dashboard_screen.dart';
import '../monitoring/live_monitor_screen.dart';
import '../incidents/enhanced_incidents_screen.dart';
import '../settings/settings_screen.dart';
import '../../../core/theme/modern_theme.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const EnhancedDashboardScreen(),
    const LiveMonitorScreen(),
    const EnhancedIncidentsScreen(),
    const SettingsScreen(),
  ];

  final List<_NavItem> _navItems = [
    _NavItem(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
    ),
    _NavItem(
      id: 'monitor',
      label: 'Live Monitor',
      icon: Icons.radio_button_unchecked,
      activeIcon: Icons.radio_button_checked,
    ),
    _NavItem(
      id: 'incidents',
      label: 'Incidents',
      icon: Icons.description_outlined,
      activeIcon: Icons.description,
    ),
    _NavItem(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _CustomBottomNav(
        currentIndex: _currentIndex,
        items: _navItems,
        onTap: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}

class _NavItem {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  _NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class _CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> items;
  final Function(int) onTap;

  const _CustomBottomNav({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor.withValues(alpha: 0.8),
        border: const Border(
          top: BorderSide(color: AppTheme.borderColor, width: 1),
        ),
        // Glass effect
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(
                    items.length,
                    (index) => Expanded(
                      child: _NavButton(
                        item: items[index],
                        isActive: currentIndex == index,
                        onTap: () => onTap(index),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active indicator line at top
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: 2,
              width: isActive ? 32 : 0,
              decoration: BoxDecoration(
                gradient: isActive ? AppTheme.primaryGradient : null,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? item.activeIcon : item.icon,
                key: ValueKey(isActive),
                size: 20,
                color: isActive ? AppTheme.primaryColor : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isActive ? AppTheme.primaryColor : AppTheme.textMuted,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
