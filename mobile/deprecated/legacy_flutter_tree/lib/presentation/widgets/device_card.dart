import 'package:flutter/material.dart';
import '../../core/theme/modern_theme.dart';

enum DeviceType { glove, glasses }

class DeviceCard extends StatefulWidget {
  final String name;
  final DeviceType type;
  final bool connected;
  final int battery;
  final int signalStrength;
  final String lastSync;

  const DeviceCard({
    super.key,
    required this.name,
    required this.type,
    required this.connected,
    required this.battery,
    required this.signalStrength,
    required this.lastSync,
  });

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getBatteryColor() {
    if (widget.battery > 60) return AppTheme.safeColor;
    if (widget.battery > 30) return AppTheme.warningColor;
    return AppTheme.dangerColor;
  }

  List<Widget> _getSignalBars() {
    final bars = (widget.signalStrength / 25).ceil();
    return List.generate(4, (i) {
      return Container(
        width: 4,
        height: 8.0 + (i * 4.0),
        decoration: BoxDecoration(
          color: i < bars
              ? AppTheme.primaryColor
              : AppTheme.textMuted.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    });
  }

  IconData _getConnectionIcon() {
    return widget.type == DeviceType.glove ? Icons.bluetooth : Icons.wifi;
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Opacity(
          opacity: widget.connected ? 1.0 : 0.6,
          child: Container(
            decoration: BoxDecoration(
              color: widget.connected
                  ? AppTheme.cardColor
                  : AppTheme.cardColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.connected
                    ? AppTheme.primaryColor.withValues(alpha: 0.3)
                    : AppTheme.borderColor,
                width: 1,
              ),
              boxShadow: widget.connected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.connected
                            ? AppTheme.primaryColor.withValues(alpha: 0.2)
                            : AppTheme.textMuted.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getConnectionIcon(),
                        size: 16,
                        color: widget.connected
                            ? AppTheme.primaryColor
                            : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.connected ? 'Connected' : 'Disconnected',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.connected
                                  ? AppTheme.safeColor
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status dot with pulse animation
                    widget.connected
                        ? _PulsingDot()
                        : Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.textMuted,
                            ),
                          ),
                  ],
                ),
                const SizedBox(height: 12),
                // Metrics
                Row(
                  children: [
                    // Battery
                    Flexible(
                      flex: 1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.battery_std,
                            size: 14,
                            color: _getBatteryColor(),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.battery}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _getBatteryColor(),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Signal Strength
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _getSignalBars()
                          .map(
                            (bar) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: bar,
                            ),
                          )
                          .toList(),
                    ),

                    const SizedBox(width: 8),

                    // Last Sync
                    Flexible(
                      flex: 1,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 12,
                            color: AppTheme.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              widget.lastSync,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Pulsing dot widget for connected status
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.safeColor.withValues(alpha: _animation.value),
          ),
        );
      },
    );
  }
}
