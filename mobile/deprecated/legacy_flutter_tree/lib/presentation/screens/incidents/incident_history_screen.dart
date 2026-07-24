import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:developer' as dev;

class IncidentHistoryScreen extends StatefulWidget {
  const IncidentHistoryScreen({super.key});

  @override
  State<IncidentHistoryScreen> createState() => _IncidentHistoryScreenState();
}

class _IncidentHistoryScreenState extends State<IncidentHistoryScreen> with SingleTickerProviderStateMixin {
  String selectedFilter = 'All';
  final List<String> filters = ['All', 'Motion', 'Weapon', 'Voice', 'Manual'];
  late AnimationController _listController;
  
  List<Map<String, dynamic>> incidents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _listController.forward();
    _fetchIncidents();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }
  
  // Fetch mock incidents (no backend needed)
  Future<void> _fetchIncidents() async {
    try {
      setState(() => _isLoading = true);
      
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Mock incidents data
      final mockIncidents = [
        {
          'incident_type': 'motion_detection',
          'timestamp': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
          'location': 'Front Door',
          'severity': 'medium',
          'confidence': 0.92,
        },
        {
          'incident_type': 'voice_detection',
          'timestamp': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
          'location': 'Living Room',
          'severity': 'high',
          'confidence': 0.87,
        },
        {
          'incident_type': 'weapon_detection',
          'timestamp': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          'location': 'Kitchen',
          'severity': 'high',
          'confidence': 0.95,
        },
      ];
      
      setState(() {
        incidents = mockIncidents.map((incident) {
          return _formatIncidentForDisplay(incident);
        }).toList();
        
        // Sort by date (most recent first)
        incidents.sort((a, b) {
          final dateA = DateTime.parse(a['date']);
          final dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        });
        
        _isLoading = false;
      });
      
      dev.log('DEBUG: Loaded ${incidents.length} mock incidents');
    } catch (e) {
      dev.log('DEBUG: Error fetching incidents: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Format incident data from backend to display format
  Map<String, dynamic> _formatIncidentForDisplay(Map<String, dynamic> incident) {
    // Map incident type to display properties
    String incidentType = incident['incident_type']?.toString() ?? 'Unknown';
    IconData icon;
    Color iconColor;
    
    switch (incidentType.toLowerCase()) {
      case 'motion':
      case 'motion_detection':
        icon = Icons.graphic_eq;
        iconColor = const Color(0xFFFBBF24);
        incidentType = 'Motion Detection';
        break;
      case 'voice':
      case 'voice_detection':
        icon = Icons.mic;
        iconColor = const Color(0xFFEF4444);
        incidentType = 'Voice Detection';
        break;
      case 'weapon':
      case 'weapon_detection':
        icon = Icons.warning;
        iconColor = const Color(0xFFEF4444);
        incidentType = 'Weapon Detection';
        break;
      case 'manual':
      case 'sos':
        icon = Icons.touch_app;
        iconColor = const Color(0xFF10B981);
        incidentType = 'Manual SOS';
        break;
      default:
        icon = Icons.info_outline;
        iconColor = const Color(0xFF9CA3AF);
    }
    
    // Map severity to color
    String severity = incident['severity']?.toString().toLowerCase() ?? 'low';
    Color severityColor;
    switch (severity) {
      case 'critical':
      case 'high':
        severityColor = const Color(0xFFEF4444);
        break;
      case 'medium':
        severityColor = const Color(0xFFFBBF24);
        break;
      default:
        severityColor = const Color(0xFF10B981);
    }
    
    // Map status to color
    String status = incident['status']?.toString() ?? 'Resolved';
    Color statusColor;
    switch (status.toLowerCase()) {
      case 'active':
        statusColor = const Color(0xFFFBBF24);
        break;
      case 'resolved':
        statusColor = const Color(0xFF10B981);
        break;
      default:
        statusColor = const Color(0xFF9CA3AF);
    }
    
    // Format date
    String formattedDate;
    try {
      final date = DateTime.parse(incident['created_at']);
      formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      formattedDate = incident['created_at']?.toString() ?? 'Unknown';
    }
    
    return {
      'type': incidentType,
      'icon': icon,
      'iconColor': iconColor,
      'severity': severity,
      'severityColor': severityColor,
      'description': incident['details']?.toString() ?? 'No description available',
      'date': formattedDate,
      'location': incident['location']?.toString() ?? 'Location unknown',
      'status': status,
      'statusColor': statusColor,
      'hasMedia': incident['media_url'] != null && incident['media_url'].toString().isNotEmpty,
      'confidence': incident['confidence_score'],
    };
  }

  @override
  Widget build(BuildContext context) {
    final filteredIncidents = selectedFilter == 'All'
        ? incidents
        : incidents.where((incident) {
            return incident['type'].toString().toLowerCase().contains(selectedFilter.toLowerCase());
          }).toList();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF0F0F0F),
              Color(0xFF0A0A0A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Header with back button
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Back button
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 24,
                      ),
                      const SizedBox(width: 12),
                      // Title
                      const Expanded(
                        child: Text(
                          'Incident History',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Count
                      Text(
                        '${incidents.length} total',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: filters.map((filter) {
                        final isSelected = selectedFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filter),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                selectedFilter = filter;
                              });
                            },
                            backgroundColor: const Color(0xFF1E293B),
                            selectedColor: const Color(0xFF6366F1),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF334155),
                            ),
                            showCheckmark: false,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Incident List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                      ),
                    )
                  : filteredIncidents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: Color(0xFF475569),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                incidents.isEmpty 
                                    ? 'No incidents recorded yet'
                                    : 'No ${selectedFilter.toLowerCase()} incidents found',
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                incidents.isEmpty
                                    ? 'All your safety incidents will appear here'
                                    : 'Try selecting a different filter',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchIncidents,
                          color: const Color(0xFF6366F1),
                          backgroundColor: const Color(0xFF1E293B),
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredIncidents.length,
                            itemBuilder: (context, index) {
                              final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
                                CurvedAnimation(
                                  parent: _listController,
                                  curve: Interval(
                                    index * 0.1,
                                    math.min(1.0, (index + 1) * 0.1 + 0.3),
                                    curve: Curves.easeOut,
                                  ),
                                ),
                              );
                              
                              final slideAnimation = Tween<Offset>(
                                begin: const Offset(0.3, 0),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: _listController,
                                  curve: Interval(
                                    index * 0.1,
                                    math.min(1.0, (index + 1) * 0.1 + 0.3),
                                    curve: Curves.easeOut,
                                  ),
                                ),
                              );

                              final incident = filteredIncidents[index];
                              return FadeTransition(
                                opacity: animation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildIncidentCard(incident),
                      ),
                    ),
                  );
                },
              ),
            ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncidentCard(Map<String, dynamic> incident) {
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
          color: incident['severityColor'].withValues(alpha: 0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: incident['severityColor'].withValues(alpha: 0.2),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: incident['iconColor'].withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  incident['icon'],
                  color: incident['iconColor'],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            incident['type'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: incident['severityColor'].withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: incident['severityColor'],
                              width: 1,
                            ),
                          ),
                          child: Text(
                            incident['severity'],
                            style: TextStyle(
                              color: incident['severityColor'],
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            incident['description'],
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.access_time,
                color: Color(0xFF64748B),
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                incident['date'],
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 16),
              const Icon(
                Icons.location_on_outlined,
                color: Color(0xFF64748B),
                size: 14,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  incident['location'],
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Row(
                children: [
                  Icon(
                    incident['status'] == 'Resolved' ? Icons.check_circle : Icons.access_time,
                    color: incident['statusColor'],
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    incident['status'],
                    style: TextStyle(
                      color: incident['statusColor'],
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (incident['hasMedia']) ...[
                const SizedBox(width: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.photo_library,
                      color: Color(0xFF6366F1),
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Media attached',
                      style: TextStyle(
                        color: Color(0xFF6366F1),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
