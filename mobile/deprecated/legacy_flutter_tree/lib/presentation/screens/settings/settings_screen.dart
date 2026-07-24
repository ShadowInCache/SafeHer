import 'package:flutter/material.dart';
import '../../../core/theme/modern_theme.dart';
import '../contacts/emergency_contacts_screen.dart';

class Contact {
  final String id;
  final String name;
  final String phone;
  final String relation;

  Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
  });
}

class SettingGroup {
  final String title;
  final List<SettingItem> items;

  SettingGroup({required this.title, required this.items});
}

class SettingItem {
  final IconData icon;
  final String label;
  final String value;

  SettingItem({required this.icon, required this.label, required this.value});
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Contact> _contacts;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _animationController.forward();

    _contacts = [
      Contact(
        id: '1',
        name: 'Sarah Johnson',
        phone: '+1 555-0123',
        relation: 'Mother',
      ),
      Contact(
        id: '2',
        name: 'Mike Chen',
        phone: '+1 555-0456',
        relation: 'Partner',
      ),
      Contact(
        id: '3',
        name: 'Officer Davis',
        phone: '+1 555-0789',
        relation: 'Local Police',
      ),
    ];
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  List<SettingGroup> _getSettingsGroups() {
    return [
      SettingGroup(
        title: 'Notifications',
        items: [
          SettingItem(
            icon: Icons.notifications,
            label: 'Push Notifications',
            value: 'On',
          ),
          SettingItem(
            icon: Icons.notifications,
            label: 'Sound Alerts',
            value: 'Vibrate',
          ),
        ],
      ),
      SettingGroup(
        title: 'Monitoring',
        items: [
          SettingItem(
            icon: Icons.shield,
            label: 'Auto SOS Threshold',
            value: '75/100',
          ),
          SettingItem(
            icon: Icons.battery_charging_full,
            label: 'Battery Saver Mode',
            value: 'Off',
          ),
          SettingItem(
            icon: Icons.location_on,
            label: 'Location Sharing',
            value: 'Emergency Only',
          ),
        ],
      ),
      SettingGroup(
        title: 'Privacy',
        items: [
          SettingItem(
            icon: Icons.dark_mode,
            label: 'Dark Mode',
            value: 'Always',
          ),
          SettingItem(
            icon: Icons.shield,
            label: 'Data Encryption',
            value: 'Enabled',
          ),
        ],
      ),
    ];
  }

  void _deleteContact(String id) {
    setState(() {
      _contacts.removeWhere((contact) => contact.id == id);
    });
  }

  void _addContact() {
    // Navigate to Emergency Contacts management screen
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const EmergencyContactsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Profile Section
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _animationController,
                curve: Curves.easeOut,
              ),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOut,
                      ),
                    ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Alex Rivera',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'alex.rivera@email.com',
                              style: TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'SafeHer Premium',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                    color: AppTheme.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                IconButton(
                  onPressed: _addContact,
                  icon: const Icon(
                    Icons.add,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._contacts.asMap().entries.map((entry) {
              final index = entry.key;
              final contact = entry.value;
              return _ContactCard(
                contact: contact,
                index: index,
                animationController: _animationController,
                onDelete: () => _deleteContact(contact.id),
              );
            }),
            const SizedBox(height: 24),

            // Settings Groups
            ..._getSettingsGroups().map((group) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.title.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      children: group.items.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final isLast = index == group.items.length - 1;
                        return _SettingItemWidget(
                          item: item,
                          showDivider: !isLast,
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final Contact contact;
  final int index;
  final AnimationController animationController;
  final VoidCallback onDelete;

  const _ContactCard({
    required this.contact,
    required this.index,
    required this.animationController,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animationController,
        curve: Interval(
          0.1 + (index * 0.05),
          0.3 + (index * 0.05),
          curve: Curves.easeOut,
        ),
      ),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.1, 0),
          end: Offset.zero,
        ).animate(animation),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.phone,
                  color: AppTheme.primaryColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${contact.relation} · ${contact.phone}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppTheme.textMuted,
                  size: 14,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                hoverColor: AppTheme.dangerColor.withValues(alpha: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingItemWidget extends StatelessWidget {
  final SettingItem item;
  final bool showDivider;

  const _SettingItemWidget({required this.item, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            // TODO: Navigate to setting detail
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(item.icon, color: AppTheme.textMuted, size: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  item.value,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textMuted,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
        if (showDivider) Container(height: 1, color: AppTheme.borderColor),
      ],
    );
  }
}
