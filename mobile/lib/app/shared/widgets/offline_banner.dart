import 'package:flutter/material.dart';

class OfflineBanner extends StatelessWidget {
  final bool offline;

  const OfflineBanner({super.key, required this.offline});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: offline ? 38 : 0,
      curve: Curves.easeOut,
      width: double.infinity,
      color: const Color(0xFFF97316),
      child: offline
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Offline mode: data is being cached securely',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
