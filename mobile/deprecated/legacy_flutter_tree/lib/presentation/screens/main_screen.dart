import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:safeher_app/presentation/screens/home/home_screen.dart';
import 'package:safeher_app/presentation/screens/monitoring/monitoring_screen.dart';
import 'package:safeher_app/presentation/screens/incidents/incident_history_screen.dart';
import 'package:safeher_app/presentation/screens/profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late PageController _pageController;
  late AnimationController _navAnimController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _navAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _navAnimController.dispose();
    super.dispose();
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    const MonitoringScreen(),
    const IncidentHistoryScreen(),
    const ProfileScreen(),
  ];

  void _onNavTap(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _screens,
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1E293B).withValues(alpha: 0.8),
                  const Color(0xFF334155).withValues(alpha: 0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border(
                top: BorderSide(
                  color: const Color(0xFF475569).withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(Icons.grid_view_rounded, 'Dashboard', 0),
                    _buildNavItem(Icons.radio_button_checked, 'Live Monitor', 1),
                    _buildNavItem(Icons.description_outlined, 'Incidents', 2),
                    _buildNavItem(Icons.settings_outlined, 'Settings', 3),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isSelected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Expanded(
          child: InkWell(
            onTap: () => _onNavTap(index),
            child: Stack(
              children: [
                // Animated gradient top indicator
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  top: isSelected ? 0 : -4,
                  left: 8,
                  right: 8,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isSelected ? 1.0 : 0.0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF8B5CF6), // Purple
                            Color(0xFFEC4899), // Pink
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [],
                      ),
                    ),
                  ),
                ),
                // Icon and label
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        color: Color.lerp(
                          const Color(0xFF94A3B8),
                          const Color(0xFF8B5CF6),
                          value,
                        ),
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: Color.lerp(
                            const Color(0xFF94A3B8),
                            const Color(0xFF8B5CF6),
                            value,
                          ),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
