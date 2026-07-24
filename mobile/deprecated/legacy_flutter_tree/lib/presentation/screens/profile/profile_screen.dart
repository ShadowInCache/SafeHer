import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  bool pushNotifications = true;
  bool soundAlerts = true;
  bool batterySaverMode = false;
  bool darkMode = true;
  double autoSOSThreshold = 75;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  final List<Map<String, dynamic>> emergencyContacts = [
    {
      'name': 'Sarah Johnson',
      'role': 'Mother',
      'phone': '+1 555-0123',
      'icon': Icons.person,
    },
    {
      'name': 'Mike Chen',
      'role': 'Partner',
      'phone': '+1 555-0456',
      'icon': Icons.person,
    },
    {
      'name': 'Officer Davis',
      'role': 'Local Police',
      'phone': '+1 555-0789',
      'icon': Icons.local_police,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF0F0F0F),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Profile Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: 0.2),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Alex Rivera',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'alex.rivera@email.com',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF6366F1),
                                width: 1,
                              ),
                            ),
                            child: const Text(
                              'SafeHer Premium',
                              style: TextStyle(
                                color: Color(0xFF6366F1),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Emergency Contacts Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'EMERGENCY CONTACTS',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFF6366F1),
                    onPressed: () {
                      // Add contact functionality
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ...emergencyContacts.map((contact) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildContactCard(contact),
                  )),
              const SizedBox(height: 24),

              // Notifications Section
              const Text(
                'NOTIFICATIONS',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              
              _buildSettingToggle(
                icon: Icons.notifications,
                title: 'Push Notifications',
                value: pushNotifications,
                onChanged: (value) {
                  setState(() {
                    pushNotifications = value;
                  });
                },
                trailing: 'On',
              ),
              const SizedBox(height: 8),
              
              _buildSettingToggle(
                icon: Icons.volume_up,
                title: 'Sound Alerts',
                value: soundAlerts,
                onChanged: (value) {
                  setState(() {
                    soundAlerts = value;
                  });
                },
                trailing: 'Vibrate',
              ),
              const SizedBox(height: 24),

              // Monitoring Section
              const Text(
                'MONITORING',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              
              _buildSliderSetting(
                icon: Icons.speed,
                title: 'Auto SOS Threshold',
                value: autoSOSThreshold,
                onChanged: (value) {
                  setState(() {
                    autoSOSThreshold = value;
                  });
                },
                trailing: '${autoSOSThreshold.toInt()}/100',
              ),
              const SizedBox(height: 8),
              
              _buildSettingToggle(
                icon: Icons.battery_saver,
                title: 'Battery Saver Mode',
                value: batterySaverMode,
                onChanged: (value) {
                  setState(() {
                    batterySaverMode = value;
                  });
                },
                trailing: 'Off',
              ),
              const SizedBox(height: 8),
              
              _buildSettingItem(
                icon: Icons.location_on,
                title: 'Location Sharing',
                trailing: 'Emergency Only',
              ),
              const SizedBox(height: 24),

              // Privacy Section
              const Text(
                'PRIVACY',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              
              _buildSettingToggle(
                icon: Icons.dark_mode,
                title: 'Dark Mode',
                value: darkMode,
                onChanged: (value) {
                  setState(() {
                    darkMode = value;
                  });
                },
                trailing: 'Always',
              ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Widget _buildContactCard(Map<String, dynamic> contact) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B).withValues(alpha: 0.8),
            const Color(0xFF0f3460).withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              contact['icon'],
              color: const Color(0xFF6366F1),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${contact['role']} · ${contact['phone']}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: const Color(0xFF64748B),
            onPressed: () {
              // Delete contact functionality
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
    required String trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF94A3B8),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF64748B),
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting({
    required IconData icon,
    required String title,
    required double value,
    required Function(double) onChanged,
    required String trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF94A3B8),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF64748B),
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF94A3B8),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF64748B),
            size: 20,
          ),
        ],
      ),
    );
  }
}
