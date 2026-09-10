import 'package:flutter/material.dart';
import '../../data/device_providers.dart';
import '../../../../shared/utils/user_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../data/ble_providers.dart';
import '../../data/motion_data_providers.dart';
import '../../domain/models/ble_models.dart';
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
class DeviceExpandableCard extends ConsumerStatefulWidget {
  const DeviceExpandableCard({
    required this.device,
    super.key,
    this.initiallyExpanded = false,
  });

  final DeviceDetail device;
  final bool initiallyExpanded;

  @override
  ConsumerState<DeviceExpandableCard> createState() => DeviceExpandableCardState();
}

class DeviceExpandableCardState extends ConsumerState<DeviceExpandableCard> {
  late bool _expanded = widget.initiallyExpanded;
  bool _unpairing = false;

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // For a glove this app has connected to live over BLE this session,
    // the real connection state is a truer "online" than the backend's
    // heartbeat-based `device.isOnline` — this firmware sends motion over
    // BLE directly and never calls the heartbeat endpoint, so
    // `device.isOnline` would otherwise show offline even while connected.
    final connectedGloveId = ref.watch(connectedGloveIdProvider);
    final bool isOnline;
    if (device.type == DeviceType.glove && connectedGloveId != null) {
      isOnline =
          ref.watch(gloveConnectionStateProvider(connectedGloveId)).valueOrNull == BleConnectionStatus.connected;
    } else {
      isOnline = device.isOnline;
    }

    return SaCard(
      onTap: () => setState(() => _expanded = !_expanded),
      semanticsLabel:
          '${device.name}, ${isOnline ? "online" : "offline"}, ${_expanded ? "expanded" : "collapsed"}, double tap to ${_expanded ? "collapse" : "expand"}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SaIcon(
                    _glyphFor(device.type),
                    size: 32,
                    color: AppColors.violet500,
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    child: Text(
                      device.name,
                      style: AppTypography.headingS.copyWith(color: onSurface),
                    ),
                  ),
                  SaStatusDot(
                    color: isOnline ? AppColors.success500 : AppColors.neutral500,
                    live: isOnline,
                    semanticsLabel: isOnline ? 'Online' : 'Offline',
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
                style: AppTypography.bodyS.copyWith(
                  color: onSurface.withValues(alpha: 0.5),
                ),
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
                    style: AppTypography.monoDataS.copyWith(
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: device.updateAvailable
                          ? AppColors.coral500.withValues(alpha: 0.15)
                          : AppColors.success500.withValues(alpha: 0.15),
                      borderRadius: AppRadius.fullRadius,
                    ),
                    child: Text(
                      device.updateAvailable
                          ? 'Update Available'
                          : 'Up to date',
                      style: AppTypography.labelM.copyWith(
                        color: device.updateAvailable
                            ? AppColors.coral500
                            : AppColors.success500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _expanded
                ? _buildExpandedContent(context, onSurface)
                : const SizedBox(width: double.infinity),
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
          if (device.type == DeviceType.glove) ...[
            const _MotionRiskDisplay(),
          ] else ...[
            _Device3DVisual(type: device.type),
            const SizedBox(height: AppSpacing.space4),
            Row(
              children: [
                Expanded(
                  child: _SensorReadout(
                    label: 'Accel',
                    value: '${device.sensors.accelG.toStringAsFixed(2)}g',
                  ),
                ),
                Expanded(
                  child: _SensorReadout(
                    label: 'Gyro',
                    value: '${device.sensors.gyroDps.toStringAsFixed(1)}°/s',
                  ),
                ),
                Expanded(
                  child: _SensorReadout(
                    label: 'Flex',
                    value: '${device.sensors.flexPercent.round()}%',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          SaButton(
            label: 'Calibrate',
            variant: SaButtonVariant.secondary,
            fullWidth: true,
            onPressed: () =>
                showSaToast(context, message: 'Calibrating ${device.name}…'),
          ),
          const SizedBox(height: AppSpacing.space2),
          SaButton(
            label: _unpairing ? 'Removing…' : 'Remove Device',
            variant: SaButtonVariant.danger,
            fullWidth: true,
            // Two taps, because this is not undoable from the app: pairing
            // again means being in Bluetooth range of the wearable, which the
            // person removing a lost or stolen one is not.
            confirmRequired: true,
            isLoading: _unpairing,
            semanticsLabel: 'Remove ${device.name} from your account',
            onPressed: _unpairing ? null : () => _unpair(context),
          ),
        ],
      ),
    );
  }

  /// Removes the wearable from the account, server-side.
  ///
  /// Dropping only the Bluetooth link would look identical on this screen and
  /// leave the device registered — still listed, and its push tokens still
  /// receiving this account's emergency notifications.
  Future<void> _unpair(BuildContext context) async {
    setState(() => _unpairing = true);
    final name = widget.device.name;
    try {
      await ref.read(deviceRepositoryProvider).unpairDevice(widget.device.id);
      ref.invalidate(devicesProvider);
      if (context.mounted) {
        showSaToast(context, message: '$name removed', type: SaToastType.success);
      }
    } catch (error) {
      if (context.mounted) {
        final described = describeError(error, fallbackTitle: "Couldn't remove $name");
        showSaToast(
          context,
          title: described.title,
          message: described.message,
          type: SaToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _unpairing = false);
    }
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
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgRadius,
          ),
        ),
      );
    }
    return Sa3DModelViewer(
      src: _modelFor(widget.type),
      alt: '3D model of device',
      height: 200,
    );
  }
}

/// Replaces the 3D visual + Accel/Gyro/Flex row for a glove: the live
/// Motion Risk Score derived from the glove's own BLE motion
/// classification, via [motionRiskScoreProvider] — same underlying
/// [motionDataProvider] stream the pairing screen reads, no second BLE
/// connection or listener. Distinct from, and not fed into, the app's
/// overall Threat Score.
///
/// Gates on the real BLE connection state ([gloveConnectionStateProvider]),
/// not just on whether a packet has arrived recently — see
/// [LiveMotionDataNotifier]'s doc comment for why the two are not the same
/// thing. A glove that has gone offline (power cut, out of range) shows
/// `-- / 100`, never its last live reading frozen in place.
class _MotionRiskDisplay extends ConsumerWidget {
  const _MotionRiskDisplay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final deviceId = ref.watch(connectedGloveIdProvider);

    final double? score;
    final String? classification;
    final bool? connected;
    if (deviceId == null) {
      // No live BLE session this app session at all — distinct from a
      // session that connected and then went offline.
      score = null;
      classification = null;
      connected = null;
    } else {
      score = ref.watch(motionRiskScoreProvider(deviceId));
      classification = ref.watch(liveMotionDataProvider(deviceId))?.classification;
      connected = ref.watch(gloveConnectionStateProvider(deviceId)).valueOrNull == BleConnectionStatus.connected;
    }

    final Color scoreColor;
    if (score == null) {
      scoreColor = onSurface.withValues(alpha: 0.4);
    } else if (score == 0) {
      scoreColor = AppColors.success500;
    } else if (classification == 'FALL') {
      scoreColor = AppColors.coral500;
    } else {
      scoreColor = AppColors.warning500;
    }

    final statusLabel = connected == null ? null : (connected ? 'CONNECTED' : 'OFFLINE');
    final statusColor = connected == true ? AppColors.success500 : AppColors.neutral500;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space5),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.08),
        borderRadius: AppRadius.lgRadius,
      ),
      child: Semantics(
        liveRegion: true,
        label:
            '${statusLabel ?? ''} '
            '${score == null ? 'Motion Risk Score: no data' : 'Motion Risk Score: ${score.toStringAsFixed(1)} of 100, ${classification ?? ''}'}'
                .trim(),
        child: ExcludeSemantics(
          child: Column(
            children: [
              if (statusLabel != null) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SaStatusDot(color: statusColor, live: connected == true),
                    const SizedBox(width: AppSpacing.space2),
                    Text(
                      statusLabel,
                      style: AppTypography.labelM.copyWith(color: statusColor),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space3),
              ],
              Text(
                'MOTION RISK SCORE',
                style: AppTypography.eyebrow.copyWith(color: onSurface.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: AppSpacing.space2),
              Text(
                score == null ? '--' : score.toStringAsFixed(1),
                style: AppTypography.displayM.copyWith(color: scoreColor),
              ),
              Text(
                '/ 100',
                style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.5)),
              ),
              if (classification != null) ...[
                const SizedBox(height: AppSpacing.space2),
                Text(
                  classification,
                  style: AppTypography.headingS.copyWith(color: onSurface),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
        Text(
          label,
          style: AppTypography.labelM.copyWith(
            color: onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
