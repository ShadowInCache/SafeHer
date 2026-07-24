import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../models/threat_level.dart';
import '../feedback/sa_battery_bar.dart';
import '../feedback/sa_signal_bars.dart';
import '../feedback/sa_status_dot.dart';
import '../icons/sa_icon.dart';
import 'sa_card.dart';

/// Horizontal-scroll device summary card (icon, battery, signal, status).
class SaDeviceCard extends StatelessWidget {
  const SaDeviceCard({
    required this.name,
    required this.batteryPercent,
    required this.signalStrength,
    required this.isOnline,
    super.key,
    this.onTap,
    this.icon = SaIconGlyph.shield,
    this.width = 140,
    this.useBlur = true,
  });

  final String name;
  final double batteryPercent;
  final int signalStrength;
  final bool isOnline;
  final VoidCallback? onTap;
  final SaIconGlyph icon;
  final double width;
  final bool useBlur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SaCard(
        onTap: onTap,
        useBlur: useBlur,
        semanticsLabel: '$name device, ${isOnline ? "online" : "offline"}, battery ${(batteryPercent * 100).round()} percent',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SaIcon(icon, size: 32, color: AppColors.violet500),
                SaStatusDot(
                  color: isOnline ? ThreatLevel.safe.color(context) : AppColors.neutral500,
                  live: isOnline,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(name, style: AppTypography.headingS.copyWith(color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: AppSpacing.space3),
            SaBatteryBar(percent: batteryPercent),
            const SizedBox(height: AppSpacing.space2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(batteryPercent * 100).round()}%', style: AppTypography.monoDataS.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                SaSignalBars(strength: signalStrength),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
