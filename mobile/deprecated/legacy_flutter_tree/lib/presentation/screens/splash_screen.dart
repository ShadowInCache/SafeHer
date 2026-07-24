import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _glowController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    // Scale animation
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    // Glow animation
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _scaleController.forward();
    _checkAuthAndNavigate();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(seconds: 3));
    
    // Navigate directly to home screen
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F172A), // Deep navy
              Color(0xFF1E1B4B), // Deep purple
              Color(0xFF1E293B), // Slate
              Color(0xFF0A0A0A), // Near black
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative purple glow circles
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -150,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: 0.15),
                      const Color(0xFF6366F1).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Logo with glowing effect
                  AnimatedBuilder(
                    animation: Listenable.merge([_scaleAnimation, _glowAnimation]),
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6), // Purple
                            borderRadius: BorderRadius.circular(35),
                            boxShadow: [
                              // Outer glow
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withValues(alpha: _glowAnimation.value * 0.6),
                                blurRadius: 80 + (_glowAnimation.value * 40),
                                spreadRadius: 0,
                              ),
                              // Middle glow
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withValues(alpha: _glowAnimation.value * 0.8),
                                blurRadius: 40 + (_glowAnimation.value * 20),
                                spreadRadius: 0,
                              ),
                              // Inner glow
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                                blurRadius: 20,
                                spreadRadius: -5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            size: 90,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  
                  // App Name with fade in
                  FadeTransition(
                    opacity: _scaleAnimation,
                    child: const Text(
                      'SafeHer',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Tagline with fade in
                  FadeTransition(
                    opacity: _scaleAnimation,
                    child: Text(
                      'AI-Powered Women\'s Safety',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 80),
                  
                  // Loading Indicator
                  FadeTransition(
                    opacity: _scaleAnimation,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.8),
                        ),
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
