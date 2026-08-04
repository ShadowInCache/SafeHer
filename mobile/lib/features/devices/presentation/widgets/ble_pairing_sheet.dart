import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/feedback/sa_signal_bars.dart';
import '../../../../shared/components/inputs/sa_otp_field.dart';
import '../../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../../../shared/components/overlays/sa_toast.dart';

class _ScannedDevice {
  const _ScannedDevice({required this.name, required this.rssiBars});

  final String name;
  final int rssiBars;
}

/// Opens the BLE pairing flow: radar-pulse scan → found-devices list →
/// 6-digit PIN dialog, ending in a success toast.
Future<void> showBlePairingSheet(BuildContext context) {
  return showSaBottomSheet<void>(context, builder: (ctx) => const _BlePairingSheetContent());
}

class _BlePairingSheetContent extends StatefulWidget {
  const _BlePairingSheetContent();

  @override
  State<_BlePairingSheetContent> createState() => _BlePairingSheetContentState();
}

class _BlePairingSheetContentState extends State<_BlePairingSheetContent> with SingleTickerProviderStateMixin {
  late final AnimationController _radarController;
  bool _scanning = true;

  static const _found = [
    _ScannedDevice(name: 'SafeHer Ring #A2F1', rssiBars: 3),
    _ScannedDevice(name: 'SafeHer Glasses #91C4', rssiBars: 2),
  ];

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _handlePairTap(BuildContext context, String deviceName) async {
    Navigator.of(context).pop();
    final paired = await _showPinDialog(context, deviceName);
    if (paired && context.mounted) {
      showSaToast(context, message: '$deviceName paired!', type: SaToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pair a Device', style: AppTypography.headingL.copyWith(color: onSurface)),
        const SizedBox(height: AppSpacing.space5),
        SizedBox(
          height: 140,
          child: Center(
            child: AnimatedBuilder(
              animation: _radarController,
              builder: (context, child) => CustomPaint(
                size: const Size(140, 140),
                painter: _RadarPainter(progress: _radarController.value, active: _scanning),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        Text(
          _scanning ? 'Scanning for nearby devices…' : 'Found ${_found.length} devices',
          textAlign: TextAlign.center,
          style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSpacing.space4),
        if (!_scanning)
          for (final device in _found)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.space3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(device.name, style: AppTypography.bodyL.copyWith(color: onSurface)),
                  ),
                  SaSignalBars(strength: device.rssiBars),
                  const SizedBox(width: AppSpacing.space3),
                  SaButton(
                    label: 'Pair',
                    size: SaButtonSize.sm,
                    onPressed: () => _handlePairTap(context, device.name),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    canvas.drawCircle(center, 6, Paint()..color = AppColors.violet500);

    if (!active) return;
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxRadius * t;
      final paint = Paint()
        ..color = AppColors.violet500.withValues(alpha: (1 - t) * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.active != active;
}

Future<bool> _showPinDialog(BuildContext context, String deviceName) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Enter pairing PIN',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Material(type: MaterialType.transparency, child: Center(child: _PinDialog(deviceName: deviceName)));
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8 * animation.value, sigmaY: 8 * animation.value),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
  return result ?? false;
}

class _PinDialog extends StatelessWidget {
  const _PinDialog({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(AppSpacing.space5),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: AppRadius.xl2Radius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter Pairing PIN', style: AppTypography.headingL.copyWith(color: onSurface)),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Enter the 6-digit PIN shown on $deviceName.',
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: AppSpacing.space5),
          SaOTPField(onCompleted: (code) => Navigator.of(context).pop(true)),
        ],
      ),
    );
  }
}
