import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/cards/sa_card.dart';
import '../../../../shared/components/feedback/sa_battery_bar.dart';
import '../../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../../shared/components/feedback/sa_signal_bars.dart';
import '../../../../shared/components/feedback/sa_status_dot.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../../shared/components/media/sa_3d_model_viewer.dart';
import '../../../../shared/components/overlays/sa_toast.dart';
import '../../domain/models/device_detail.dart';

SaIconGlyph _glyphFor(DeviceType type) => switch (type) {
  DeviceType.ring => SaIconGlyph.ring,
  DeviceType.glasses => SaIconGlyph.camera,
  DeviceType.glove => SaIconGlyph.glove,
  DeviceType.pendant => SaIconGlyph.pendant,
};

String _modelFor(DeviceType type) => switch (type) {
  DeviceType.glove => SaSampleModels.astronaut,
  _ => SaSampleModels.shoe,
};

/// Full device row: header (icon/name/status), battery, signal, firmware,
/// tap to AnimatedSize-expand into the 3D visual + sensor grid + calibrate
/// CTA. [initiallyExpanded] supports deep-linking from Home's device tap.
class DeviceExpandableCard extends StatefulWidget {
  const DeviceExpandableCard({required this.device, super.key, this.initiallyExpanded = false});

  final DeviceDetail device;
  final bool initiallyExpanded;

  @override
  State<DeviceExpandableCard> createState() => DeviceExpandableCardState();
}

class DeviceExpandableCardState extends State<DeviceExpandableCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SaCard(
      semanticsLabel: '${device.name}, ${device.isOnline ? "online" : "offline"}, expand for details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SaIcon(_glyphFor(device.type), size: 32, color: AppColors.violet500),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Text(device.name, style: AppTypography.headingS.copyWith(color: onSurface)),
                    ),
                    SaStatusDot(
                      color: device.isOnline ? AppColors.success500 : AppColors.neutral500,
                      live: device.isOnline,
                      semanticsLabel: device.isOnline ? 'Online' : 'Offline',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space4),
                Row(
                  children: [
                    Expanded(child: SaBatteryBar(percent: device.batteryPercent)),
                    const SizedBox(width: AppSpacing.space3),
                    Text(
                      '${(device.batteryPercent * 100).round()}%',
                      style: AppTypography.monoDataS.copyWith(color: onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  '~${device.batteryHoursRemaining}h remaining',
                  style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: AppSpacing.space3),
                Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SaSignalBars(strength: device.signalStrength),
                    Text(
                      device.firmwareVersion,
                      style: AppTypography.monoDataS.copyWith(color: onSurface.withValues(alpha: 0.6)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: device.updateAvailable
                            ? AppColors.coral500.withValues(alpha: 0.15)
                            : AppColors.success500.withValues(alpha: 0.15),
                        borderRadius: AppRadius.fullRadius,
                      ),
                      child: Text(
                        device.updateAvailable ? 'Update Available' : 'Up to date',
                        style: AppTypography.labelM.copyWith(
                          color: device.updateAvailable ? AppColors.coral500 : AppColors.success500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded ? _buildExpandedContent(context, onSurface) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, Color onSurface) {
    final device = widget.device;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: AppSpacing.space3),
          _Device3DVisual(type: device.type),
          const SizedBox(height: AppSpacing.space4),
          Row(
            children: [
              Expanded(child: _SensorReadout(label: 'Accel', value: '${device.sensors.accelG.toStringAsFixed(2)}g')),
              Expanded(child: _SensorReadout(label: 'Gyro', value: '${device.sensors.gyroDps.toStringAsFixed(1)}°/s')),
              Expanded(child: _SensorReadout(label: 'Flex', value: '${device.sensors.flexPercent.round()}%')),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          SaButton(
            label: 'Calibrate',
            variant: SaButtonVariant.secondary,
            fullWidth: true,
            onPressed: () => showSaToast(context, message: 'Calibrating ${device.name}…'),
          ),
        ],
      ),
    );
  }
}

class _Device3DVisual extends StatefulWidget {
  const _Device3DVisual({required this.type});

  final DeviceType type;

  @override
  State<_Device3DVisual> createState() => _Device3DVisualState();
}

class _Device3DVisualState extends State<_Device3DVisual> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return SaLoadingShimmer(
        child: Container(height: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.lgRadius)),
      );
    }
    return Sa3DModelViewer(src: _modelFor(widget.type), alt: '3D model of device', height: 200);
  }
}

class _SensorReadout extends StatelessWidget {
  const _SensorReadout({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      children: [
        Text(value, style: AppTypography.monoDataM.copyWith(color: onSurface)),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.labelM.copyWith(color: onSurface.withValues(alpha: 0.5))),
      ],
    );
  }
}
