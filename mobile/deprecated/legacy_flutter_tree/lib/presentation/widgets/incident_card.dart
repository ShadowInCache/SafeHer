import 'package:flutter/material.dart';
import '../../core/theme/modern_theme.dart';

enum IncidentType { motion, weapon, voice, manual }

enum IncidentSeverity { low, medium, high, critical }

class IncidentCardModel {
  final String id;
  final String date;
  final String time;
  final String location;
  final IncidentType type;
  final IncidentSeverity severity;
  final String description;
  final bool hasMedia;
  final bool resolved;

  IncidentCardModel({
    required this.id,
    required this.date,
    required this.time,
    required this.location,
    required this.type,
    required this.severity,
    required this.description,
    required this.hasMedia,
    required this.resolved,
  });
}

class IncidentCard extends StatefulWidget {
  final IncidentCardModel incident;
  final int index;

  const IncidentCard({super.key, required this.incident, this.index = 0});

  @override
  State<IncidentCard> createState() => _IncidentCardState();
}

class _IncidentCardState extends State<IncidentCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-0.1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Stagger animation based on index
    Future.delayed(Duration(milliseconds: widget.index * 50), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _getTypeIcon() {
    switch (widget.incident.type) {
      case IncidentType.motion:
        return Icons.directions_run; // Activity
      case IncidentType.weapon:
        return Icons.camera_alt; // Camera
      case IncidentType.voice:
        return Icons.mic; // Mic
      case IncidentType.manual:
        return Icons.back_hand; // Hand
    }
  }

  String _getTypeLabel() {
    switch (widget.incident.type) {
      case IncidentType.motion:
        return 'Motion';
      case IncidentType.weapon:
        return 'Weapon';
      case IncidentType.voice:
        return 'Voice';
      case IncidentType.manual:
        return 'Manual';
    }
  }

  Color _getSeverityColor() {
    switch (widget.incident.severity) {
      case IncidentSeverity.low:
        return AppTheme.safeColor;
      case IncidentSeverity.medium:
        return AppTheme.warningColor;
      case IncidentSeverity.high:
        return AppTheme.dangerColor;
      case IncidentSeverity.critical:
        return AppTheme.criticalColor;
    }
  }

  String _getSeverityLabel() {
    return widget.incident.severity.name;
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _getSeverityColor();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main content
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: severityColor.withValues(alpha: 0.1),
                      border: Border.all(color: severityColor.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_getTypeIcon(), size: 16, color: severityColor),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title and severity badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_getTypeLabel()} Detection',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: severityColor.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: severityColor.withValues(alpha: 0.2),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getSeverityLabel(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: severityColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Description (line-clamp-2)
                        Text(
                          widget.incident.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Metadata
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${widget.incident.date} ${widget.incident.time}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  size: 12,
                                  color: AppTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    widget.incident.location,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.textMuted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Footer
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.borderColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.incident.resolved ? '✓ Resolved' : '● Active',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: widget.incident.resolved
                            ? AppTheme.safeColor
                            : AppTheme.warningColor,
                      ),
                    ),
                    if (widget.incident.hasMedia)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 12,
                            color: AppTheme.primaryColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Media attached',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
