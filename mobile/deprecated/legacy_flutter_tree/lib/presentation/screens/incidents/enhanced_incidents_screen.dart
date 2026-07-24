import 'package:flutter/material.dart';
import '../../widgets/incident_card.dart';
import '../../../core/theme/modern_theme.dart';

class EnhancedIncidentsScreen extends StatefulWidget {
  const EnhancedIncidentsScreen({super.key});

  @override
  State<EnhancedIncidentsScreen> createState() =>
      _EnhancedIncidentsScreenState();
}

class _EnhancedIncidentsScreenState extends State<EnhancedIncidentsScreen> {
  String _selectedFilter = 'all';

  final List<IncidentCardModel> _mockIncidents = [
    IncidentCardModel(
      id: '1',
      date: '2026-02-10',
      time: '14:23',
      location: 'Downtown, Main St',
      type: IncidentType.motion,
      severity: IncidentSeverity.medium,
      description:
          'Unusual motion pattern detected — sudden jerking movements consistent with struggle.',
      hasMedia: true,
      resolved: true,
    ),
    IncidentCardModel(
      id: '2',
      date: '2026-02-09',
      time: '22:15',
      location: 'Park Ave, Block 5',
      type: IncidentType.voice,
      severity: IncidentSeverity.high,
      description:
          'Threatening vocal patterns detected with high anger confidence. Audio recorded.',
      hasMedia: true,
      resolved: false,
    ),
    IncidentCardModel(
      id: '3',
      date: '2026-02-08',
      time: '19:47',
      location: 'Metro Station B',
      type: IncidentType.weapon,
      severity: IncidentSeverity.critical,
      description:
          'Knife detected in camera feed with 94% confidence. Emergency contacts alerted.',
      hasMedia: true,
      resolved: true,
    ),
    IncidentCardModel(
      id: '4',
      date: '2026-02-07',
      time: '23:30',
      location: 'Residence',
      type: IncidentType.manual,
      severity: IncidentSeverity.low,
      description:
          'Manual SOS triggered. User reported feeling unsafe walking home.',
      hasMedia: false,
      resolved: true,
    ),
    IncidentCardModel(
      id: '5',
      date: '2026-02-06',
      time: '08:12',
      location: 'Bus Stop, 3rd Ave',
      type: IncidentType.motion,
      severity: IncidentSeverity.low,
      description:
          'Minor motion anomaly detected. Likely false positive from running.',
      hasMedia: false,
      resolved: true,
    ),
  ];

  List<IncidentCardModel> get _filteredIncidents {
    if (_selectedFilter == 'all') {
      return _mockIncidents;
    }
    return _mockIncidents.where((incident) {
      return incident.type.name == _selectedFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header with count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Incident History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${_mockIncidents.length} total',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 14, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'All',
                    isSelected: _selectedFilter == 'all',
                    onTap: () => setState(() => _selectedFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Motion',
                    isSelected: _selectedFilter == 'motion',
                    onTap: () => setState(() => _selectedFilter = 'motion'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Weapon',
                    isSelected: _selectedFilter == 'weapon',
                    onTap: () => setState(() => _selectedFilter = 'weapon'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Voice',
                    isSelected: _selectedFilter == 'voice',
                    onTap: () => setState(() => _selectedFilter = 'voice'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Manual',
                    isSelected: _selectedFilter == 'manual',
                    onTap: () => setState(() => _selectedFilter = 'manual'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Incidents List
            if (_filteredIncidents.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: AppTheme.textMuted),
                      SizedBox(height: 16),
                      Text(
                        'No incidents found',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._filteredIncidents.asMap().entries.map((entry) {
                final index = entry.key;
                final incident = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IncidentCard(incident: incident, index: index),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
