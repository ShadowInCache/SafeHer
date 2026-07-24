import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Utility class for handling mobile-only responsive design
class ResponsiveHelper {
  // Mobile device width constants
  static const double mobileWidth = 375.0;  // iPhone-like width
  static const double mobileHeight = 812.0; // iPhone-like height
  static const double tabletBreakpoint = 768.0;
  
  /// Check if the current platform should use mobile-only layout
  static bool shouldUseMobileWrapper(BuildContext context) {
    // Only use mobile wrapper on web browsers
    if (kIsWeb) {
      return true; 
    }
    
    // On actual mobile devices (Android/iOS), never use wrapper
    return false;
  }
  
  /// Get the appropriate device frame based on the platform
  static BoxDecoration getDeviceFrame() {
    return BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: const Color(0xFF333333),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          spreadRadius: 5,
        ),
        BoxShadow(
          color: const Color(0xFF6366F1).withValues(alpha: 0.1),
          blurRadius: 30,
          spreadRadius: 10,
        ),
      ],
    );
  }
  
  /// Create a mobile device notch
  static Widget buildDeviceNotch() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 30,
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(15),
            bottomRight: Radius.circular(15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 4,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Create device home indicator (bottom bar)
  static Widget buildHomeIndicator() {
    return Positioned(
      bottom: 8,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 134,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF666666),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Enhanced mobile view wrapper with better responsiveness
/// 
/// This wrapper ensures UI consistency across platforms:
/// - Web: Shows mobile device frame for demos/development
/// - Mobile: Returns native app experience (no wrapper)
/// 
/// The content inside is IDENTICAL on both platforms!
class MobileViewWrapper extends StatelessWidget {
  final Widget child;
  final bool showNotch;
  final bool showHomeIndicator;
  
  const MobileViewWrapper({
    super.key,
    required this.child,
    this.showNotch = true,
    this.showHomeIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    // Only apply mobile wrapper on web/desktop platforms
    // On actual mobile devices, this will return the child directly
    // ensuring IDENTICAL UI experience between web preview and mobile app
    if (ResponsiveHelper.shouldUseMobileWrapper(context)) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A), // Very dark background
        body: Center(
          child: Container(
            width: ResponsiveHelper.mobileWidth,
            height: ResponsiveHelper.mobileHeight,
            decoration: ResponsiveHelper.getDeviceFrame(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  // Main app content with padding for notch
                  Positioned.fill(
                    top: showNotch ? 30 : 0,
                    bottom: showHomeIndicator ? 12 : 0,
                    child: child,
                  ),
                  
                  // Device notch
                  if (showNotch) ResponsiveHelper.buildDeviceNotch(),
                  
                  // Home indicator
                  if (showHomeIndicator) ResponsiveHelper.buildHomeIndicator(),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    // On actual mobile devices (Android/iOS), return the child as-is
    // This ensures the UI looks exactly the same as the web preview,
    // but with native mobile features (status bar, navigation, etc.)
    return child;
  }
}