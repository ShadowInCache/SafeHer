import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Debug widget to show platform information during development
class PlatformDebugInfo extends StatelessWidget {
  const PlatformDebugInfo({super.key});

  @override
  Widget build(BuildContext context) {
    // Only show in debug mode
    if (!kDebugMode) return const SizedBox.shrink();
    
    final screenSize = MediaQuery.of(context).size;
    
    return Positioned(
      top: 40,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Platform: ${kIsWeb ? "Web" : "Mobile"}',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Screen: ${screenSize.width.toInt()}x${screenSize.height.toInt()}',
              style: const TextStyle(color: Colors.white70, fontSize: 9),
            ),
            const Text(
              kIsWeb ? 'Wrapper: Active' : 'Native: Mobile',
              style: TextStyle(
                color: kIsWeb ? Colors.orange : Colors.green,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extension to easily add debug info to any screen
extension ScreenDebugExtension on Widget {
  Widget withDebugInfo() {
    return Stack(
      children: [
        this,
        const PlatformDebugInfo(),
      ],
    );
  }
}