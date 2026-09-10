import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/animations/animation_helpers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/feedback/sa_signal_bars.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../data/ble_providers.dart';
import '../../data/motion_data_providers.dart';
import '../../domain/models/ble_models.dart';
import '../../domain/models/ble_pairing_state.dart';
import '../../domain/models/device_detail.dart';
import '../../domain/models/registered_device.dart';

/// Real BLE pairing: permission request → adapter check → live scan →
/// connect + GATT service discovery → backend device registration.
///
/// ## What this flow is
///
/// Everything shown here comes from the radio or the OS. Devices in the
/// list are peripherals that genuinely advertised nearby, their names are
/// the names they actually broadcast (or "Unknown Device" when they
/// broadcast none), and the signal reading is a real RSSI. A connection is
/// only reported once `connect()` succeeded *and* `discoverServices()`
/// came back — the discovered service count is shown as the evidence.
///
/// ## What this flow is not
///
/// It is **not** the sensor-data pipe for a SafeHer wearable. Per
/// `ARCHITECTURE.md` and the ESP32 firmware in `hardware/`, the glove and
/// glasses publish telemetry to the backend over **WiFi + MQTT directly**
/// (`fastapi_app/mqtt_service.py` consumes those topics); the phone is not
/// a BLE bridge on that path, and no SafeHer BLE GATT service or
/// characteristic UUID exists anywhere in this repo. So do not build live
/// sensor reads on top of this connection — a paired device here means a
/// verified physical peripheral plus a backend registration record, and
/// nothing more.
///
/// BLE also cannot tell us which wearable a peripheral physically is,
/// which is why the user picks the [DeviceType] before registration
/// instead of the app guessing.
Future<void> showBlePairingSheet(BuildContext context) {
  return showSaBottomSheet<void>(context, builder: (ctx) => const BlePairingSheetContent());
}

/// The sheet's content, public so widget/golden tests can pump it directly
/// with a fake `BleService` injected instead of driving a modal route.
class BlePairingSheetContent extends ConsumerStatefulWidget {
  const BlePairingSheetContent({super.key});

  @override
  ConsumerState<BlePairingSheetContent> createState() => _BlePairingSheetContentState();
}

class _BlePairingSheetContentState extends ConsumerState<BlePairingSheetContent>
    with SingleTickerProviderStateMixin {
  /// Local, ephemeral, and purely decorative — the radar pulse owns no
  /// state anything outside this widget needs, so it stays a plain
  /// controller rather than going through Riverpod.
  late final AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Reduced-motion users get a static radar rather than a loop.
      AnimationHelpers.repeat(context, _radarController);
      ref.read(blePairingControllerProvider.notifier).startScan();
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(blePairingControllerProvider);
    final controller = ref.read(blePairingControllerProvider.notifier);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Pair a Device', style: AppTypography.headingL.copyWith(color: onSurface)),
        ),
        const SizedBox(height: AppSpacing.space5),
        _bodyFor(context, state, controller),
      ],
    );
  }

  Widget _bodyFor(BuildContext context, BlePairingState state, BlePairingController controller) {
    return switch (state.stage) {
      BlePairingStage.idle ||
      BlePairingStage.scanning ||
      BlePairingStage.scanComplete => _ScanView(
        state: state,
        radar: _radar(active: state.isScanning),
        onRescan: controller.startScan,
        onStopScan: controller.stopScan,
        onConnect: controller.connect,
      ),
      BlePairingStage.permissionRequired => _PermissionRequiredView(
        permanentlyDenied: state.permissionPermanentlyDenied,
        onRequest: controller.startScan,
        onOpenSettings: controller.openAppSettings,
      ),
      BlePairingStage.bluetoothDisabled => _BluetoothDisabledView(
        canPrompt: state.canPromptToEnableBluetooth,
        errorMessage: state.errorMessage,
        onEnable: controller.enableBluetooth,
        onRetry: controller.startScan,
      ),
      BlePairingStage.unsupported || BlePairingStage.scanFailed => _MessageView(
        glyph: SaIconGlyph.bluetoothOff,
        tint: AppColors.coral500,
        title: state.stage == BlePairingStage.unsupported ? 'Bluetooth Unavailable' : "Couldn't Scan",
        body: state.errorMessage ?? 'Scanning could not be started.',
        actionLabel: state.stage == BlePairingStage.unsupported ? null : 'Try Again',
        onAction: controller.startScan,
      ),
      BlePairingStage.connecting => _MessageView(
        glyph: SaIconGlyph.bluetooth,
        tint: AppColors.violet500,
        title: 'Connecting',
        body: 'Connecting to ${state.target?.displayName ?? 'device'}…',
        showProgress: true,
      ),
      BlePairingStage.reconnecting => _MessageView(
        glyph: SaIconGlyph.bluetooth,
        tint: AppColors.warning500,
        title: 'Reconnecting',
        body:
            'Attempt ${state.reconnectAttempt} of ${BlePairingController.maxReconnectAttempts} to reach '
            '${state.target?.displayName ?? 'the device'}.',
        showProgress: true,
      ),
      BlePairingStage.disconnected => _MessageView(
        glyph: SaIconGlyph.bluetoothOff,
        tint: AppColors.warning500,
        title: 'Disconnected',
        body:
            '${state.target?.displayName ?? 'The device'} went out of range or powered off. '
            'Trying to reconnect…',
        showProgress: true,
      ),
      BlePairingStage.connectionFailed => _MessageView(
        glyph: SaIconGlyph.bluetoothOff,
        tint: AppColors.coral500,
        title: 'Connection Failed',
        body: state.errorMessage ?? 'The device did not accept the connection.',
        actionLabel: 'Try Again',
        onAction: controller.retryConnection,
        secondaryActionLabel: 'Scan Again',
        onSecondaryAction: controller.startScan,
      ),
      BlePairingStage.connected ||
      BlePairingStage.registering ||
      BlePairingStage.registered => _ConnectedView(
        state: state,
        onSelectType: controller.selectDeviceType,
        onRegister: controller.registerConnectedDevice,
        onDisconnect: controller.disconnect,
      ),
    };
  }

  Widget _radar({required bool active}) {
    // Isolated so the looping pulse never repaints the device list beside it.
    return RepaintBoundary(
      child: SizedBox(
        height: 140,
        child: Center(
          child: AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) => CustomPaint(
              size: const Size(140, 140),
              painter: _RadarPainter(progress: _radarController.value, active: active),
            ),
          ),
        ),
      ),
    );
  }
}

/// Scanning + results. The list is rebuilt on every advertisement, so
/// devices appear as they are genuinely found rather than all at once.
class _ScanView extends StatelessWidget {
  const _ScanView({
    required this.state,
    required this.radar,
    required this.onRescan,
    required this.onStopScan,
    required this.onConnect,
  });

  final BlePairingState state;
  final Widget radar;
  final Future<void> Function() onRescan;
  final Future<void> Function() onStopScan;
  final Future<void> Function(BleDiscoveredDevice device) onConnect;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final devices = state.devices;
    final scanning = state.isScanning;

    final String status;
    if (scanning) {
      status = devices.isEmpty
          ? 'Scanning for nearby devices…'
          : 'Scanning — found ${devices.length} so far';
    } else if (devices.isEmpty) {
      status = 'No devices found nearby.';
    } else {
      status = 'Found ${devices.length} ${devices.length == 1 ? 'device' : 'devices'}';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        radar,
        const SizedBox(height: AppSpacing.space3),
        Semantics(
          liveRegion: true,
          child: Text(
            status,
            textAlign: TextAlign.center,
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        if (devices.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: devices.length,
              separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.space3),
              itemBuilder: (context, index) => _DeviceRow(
                device: devices[index],
                onConnect: () => onConnect(devices[index]),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.space4),
        SaButton(
          label: scanning ? 'Stop Scanning' : 'Scan Again',
          variant: SaButtonVariant.secondary,
          fullWidth: true,
          semanticsLabel: scanning ? 'Stop scanning for devices' : 'Scan again for nearby devices',
          onPressed: () => scanning ? onStopScan() : onRescan(),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onConnect});

  final BleDiscoveredDevice device;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label:
          '${device.displayName}, signal ${device.signalLabel}, '
          '${device.rssi} dBm, ${device.isConnectable ? 'available' : 'not connectable'}',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.displayName,
                  style: AppTypography.bodyL.copyWith(
                    color: onSurface,
                    // An unnamed peripheral is called out rather than dressed up.
                    fontStyle: device.hasAdvertisedName ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Signal: ${device.signalLabel} · ${device.rssi} dBm · '
                  '${device.isConnectable ? 'Available' : 'Not connectable'}',
                  style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.55)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.space3),
          ExcludeSemantics(child: SaSignalBars(strength: device.signalBars)),
          const SizedBox(width: AppSpacing.space3),
          SaButton(
            label: 'Connect',
            size: SaButtonSize.sm,
            semanticsLabel: 'Connect to ${device.displayName}',
            onPressed: device.isConnectable ? onConnect : null,
          ),
        ],
      ),
    );
  }
}

class _PermissionRequiredView extends StatelessWidget {
  const _PermissionRequiredView({
    required this.permanentlyDenied,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final bool permanentlyDenied;
  final Future<void> Function() onRequest;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return _MessageView(
      glyph: SaIconGlyph.shield,
      tint: AppColors.warning500,
      title: 'Permission Required',
      body: permanentlyDenied
          ? 'Bluetooth permission was denied for good. Open Settings and allow '
                'Bluetooth (and Location on Android) so SafeHer can find your device.'
          : 'SafeHer needs Bluetooth permission — and Location on Android, which the '
                'system requires for Bluetooth scanning — to find nearby devices.',
      actionLabel: permanentlyDenied ? 'Open Settings' : 'Grant Permission',
      onAction: permanentlyDenied ? onOpenSettings : onRequest,
      secondaryActionLabel: permanentlyDenied ? null : 'Open Settings',
      onSecondaryAction: onOpenSettings,
    );
  }
}

class _BluetoothDisabledView extends StatelessWidget {
  const _BluetoothDisabledView({
    required this.canPrompt,
    required this.errorMessage,
    required this.onEnable,
    required this.onRetry,
  });

  final bool canPrompt;
  final String? errorMessage;
  final Future<void> Function() onEnable;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _MessageView(
      glyph: SaIconGlyph.bluetoothOff,
      tint: AppColors.warning500,
      title: 'Bluetooth Disabled',
      body:
          errorMessage ??
          (canPrompt
              // iOS gives apps no API to power the radio on, so there the
              // only honest instruction is to do it manually.
              ? 'Bluetooth is turned off. Turn it on to scan for nearby devices.'
              : 'Bluetooth is turned off. Turn it on in Settings or Control Centre, '
                    'then scan again.'),
      actionLabel: canPrompt ? 'Turn On Bluetooth' : 'Scan Again',
      onAction: canPrompt ? onEnable : onRetry,
      secondaryActionLabel: canPrompt ? 'Scan Again' : null,
      onSecondaryAction: onRetry,
    );
  }
}

/// Connected → pick what the wearable physically is → register.
class _ConnectedView extends ConsumerWidget {
  const _ConnectedView({
    required this.state,
    required this.onSelectType,
    required this.onRegister,
    required this.onDisconnect,
  });

  final BlePairingState state;
  final void Function(DeviceType type) onSelectType;
  final Future<void> Function() onRegister;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final registered = state.stage == BlePairingStage.registered;
    final device = state.target;

    // Temporary: subscribe so [SAFEHER MOTION] debug logs fire, and show
    // the live reading, while connected during end-to-end BLE verification.
    // Glove-only: the glove is the only wearable that speaks this GATT
    // service, and this must never appear while pairing an unrelated
    // device type (glasses, ring, pendant) — those are owned elsewhere.
    final isGlove = state.selectedType == DeviceType.glove;
    final motionAsync = device != null && isGlove ? ref.watch(motionDataProvider(device.id)) : null;
    final motion = motionAsync?.value;
    final motionRiskScore = device != null && isGlove ? ref.watch(motionRiskScoreProvider(device.id)) : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlyphBadge(glyph: SaIconGlyph.bluetooth, tint: AppColors.success500),
        const SizedBox(height: AppSpacing.space4),
        Semantics(
          liveRegion: true,
          child: Text(
            registered ? 'Device Registered' : 'Connected',
            textAlign: TextAlign.center,
            style: AppTypography.headingM.copyWith(color: onSurface),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          device?.displayName ?? 'Device',
          textAlign: TextAlign.center,
          style: AppTypography.bodyL.copyWith(color: onSurface),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          // The service count is the proof the link is real, not decoration.
          '${state.serviceCount} GATT ${state.serviceCount == 1 ? 'service' : 'services'} discovered',
          textAlign: TextAlign.center,
          style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
        ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: AppSpacing.space3),
          Text(
            state.errorMessage!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyM.copyWith(color: AppColors.coral500),
          ),
        ],
        if (motion != null) ...[
          const SizedBox(height: AppSpacing.space3),
          Semantics(
            liveRegion: true,
            child: Text(
              'Motion: ${motion.classification} (${(motion.confidence * 100).toStringAsFixed(1)}%)',
              textAlign: TextAlign.center,
              style: AppTypography.bodyM.copyWith(
                color: AppColors.violet500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (device != null && isGlove) ...[
          const SizedBox(height: AppSpacing.space2),
          Semantics(
            liveRegion: true,
            child: Text(
              motionRiskScore == null
                  ? 'Motion Risk: --'
                  : 'Motion Risk: ${motionRiskScore.toStringAsFixed(1)} / 100',
              textAlign: TextAlign.center,
              style: AppTypography.bodyM.copyWith(color: onSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.space5),
        if (!registered) ...[
          Text(
            'What kind of device is this?',
            style: AppTypography.labelL.copyWith(color: onSurface),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            "Bluetooth can't tell which wearable this is, so pick it yourself.",
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.space3),
          _DeviceTypePicker(selected: state.selectedType, onSelect: onSelectType),
          const SizedBox(height: AppSpacing.space5),
          SaButton(
            label: 'Register Device',
            fullWidth: true,
            isLoading: state.stage == BlePairingStage.registering,
            semanticsLabel: 'Register this device with SafeHer',
            onPressed: state.stage == BlePairingStage.registering ? null : () => onRegister(),
          ),
          const SizedBox(height: AppSpacing.space3),
        ] else ...[
          Text(
            'Registered as ${state.registeredDevice?.deviceType.label ?? state.selectedType.label}.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.space5),
        ],
        SaButton(
          label: 'Disconnect',
          variant: SaButtonVariant.danger,
          fullWidth: true,
          semanticsLabel: 'Disconnect from ${device?.displayName ?? 'this device'}',
          onPressed: () => onDisconnect(),
        ),
      ],
    );
  }
}

class _DeviceTypePicker extends StatelessWidget {
  const _DeviceTypePicker({required this.selected, required this.onSelect});

  final DeviceType selected;
  final void Function(DeviceType type) onSelect;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      children: [
        for (final type in DeviceType.values)
          Semantics(
            label: '${type.label} device type',
            button: true,
            selected: type == selected,
            child: InkWell(
              onTap: () => onSelect(type),
              borderRadius: AppRadius.fullRadius,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space4,
                  vertical: AppSpacing.space2,
                ),
                decoration: BoxDecoration(
                  color: type == selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                  border: Border.all(
                    color: type == selected ? AppColors.violet500 : onSurface.withValues(alpha: 0.3),
                  ),
                  borderRadius: AppRadius.fullRadius,
                ),
                child: Text(
                  type.label,
                  style: AppTypography.labelM.copyWith(
                    color: type == selected ? Theme.of(context).colorScheme.onPrimary : onSurface,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shared layout for every non-list state: glyph, title, explanation, and
/// up to two actions.
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.glyph,
    required this.tint,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.showProgress = false,
  });

  final SaIconGlyph glyph;
  final Color tint;
  final String title;
  final String body;
  final String? actionLabel;
  final Future<void> Function()? onAction;
  final String? secondaryActionLabel;
  final Future<void> Function()? onSecondaryAction;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlyphBadge(glyph: glyph, tint: tint),
        const SizedBox(height: AppSpacing.space4),
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.headingM.copyWith(color: onSurface),
          ),
        ),
        const SizedBox(height: AppSpacing.space2),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.7)),
        ),
        if (showProgress) ...[
          const SizedBox(height: AppSpacing.space4),
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.violet500),
            ),
          ),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: AppSpacing.space5),
          SaButton(
            label: actionLabel!,
            fullWidth: true,
            semanticsLabel: actionLabel,
            onPressed: onAction == null ? null : () => onAction!(),
          ),
        ],
        if (secondaryActionLabel != null) ...[
          const SizedBox(height: AppSpacing.space3),
          SaButton(
            label: secondaryActionLabel!,
            variant: SaButtonVariant.secondary,
            fullWidth: true,
            semanticsLabel: secondaryActionLabel,
            onPressed: onSecondaryAction == null ? null : () => onSecondaryAction!(),
          ),
        ],
      ],
    );
  }
}

class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge({required this.glyph, required this.tint});

  final SaIconGlyph glyph;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: SaIcon(glyph, size: 32, color: tint),
      ),
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
