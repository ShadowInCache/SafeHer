import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme/modern_theme.dart';

class SOSButton extends StatefulWidget {
  final VoidCallback onActivate;

  const SOSButton({super.key, required this.onActivate});

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> with TickerProviderStateMixin {
  bool _isPressed = false;
  int _countdown = 10;
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for pressed state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Scale animation for text transitions
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onPressStart() {
    setState(() {
      _isPressed = true;
      _countdown = 10;
    });

    // Start pulse animation
    _pulseController.repeat(reverse: true);
    _scaleController.forward(from: 0.0);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });

      if (_countdown <= 0) {
        timer.cancel();
        widget.onActivate();
        _onPressEnd();
      }
    });
  }

  void _onPressEnd() {
    _countdownTimer?.cancel();
    _pulseController.stop();
    _scaleController.forward(from: 0.0);
    setState(() {
      _isPressed = false;
      _countdown = 10;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => _onPressStart(),
          onTapUp: (_) => _onPressEnd(),
          onTapCancel: () => _onPressEnd(),
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulseAnimation, _scaleAnimation]),
            builder: (context, child) {
              final buttonScale = _isPressed ? 0.95 : 1.0;
              final pulseScale = _isPressed ? _pulseAnimation.value : 1.0;

              return Transform.scale(
                scale: buttonScale,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.dangerGradient,
                    boxShadow: _isPressed
                        ? [
                            BoxShadow(
                              color: AppTheme.dangerColor.withValues(alpha: 
                                0.6 * pulseScale,
                              ),
                              blurRadius: 30 * pulseScale,
                              spreadRadius: 5 * pulseScale,
                            ),
                          ]
                        : AppTheme.glowShadow(AppTheme.dangerColor),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Inner border circle
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                      ),

                      // Text with smooth scale animation
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              return ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.5,
                                  end: 1.0,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                        child: _isPressed
                            ? Text(
                                '$_countdown',
                                key: ValueKey(_countdown),
                                style: const TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                  height: 1.0,
                                ),
                              )
                            : const Text(
                                'SOS',
                                key: ValueKey('sos'),
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 6,
                                  height: 1.0,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        Text(
          _isPressed ? 'Release to cancel' : 'Press & hold for emergency',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[400],
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
