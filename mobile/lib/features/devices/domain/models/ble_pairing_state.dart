import 'ble_models.dart';
import 'device_detail.dart';
import 'registered_device.dart';

/// Every distinct place the pairing flow can genuinely be.
///
/// Each one corresponds to something the radio, the OS, or the backend
/// actually told us — none of them is a cosmetic step on a timer.
enum BlePairingStage {
  /// Nothing started yet, or a device was deliberately disconnected.
  idle,

  /// The OS refused the Bluetooth/location permissions a scan needs.
  permissionRequired,

  /// The adapter is powered off.
  bluetoothDisabled,

  /// This hardware has no BLE at all.
  unsupported,

  /// A scan is running; [BlePairingState.devices] fills in live.
  scanning,

  /// The scan's timeout elapsed and the radio stopped.
  scanComplete,

  /// The scan could not be started (see [BlePairingState.errorMessage]).
  scanFailed,

  /// A `connect()` + `discoverServices()` attempt is in flight.
  connecting,

  /// Connected, with GATT services discovered.
  connected,

  /// Registering the connected device with the backend.
  registering,

  /// The backend has the device on record.
  registered,

  /// The connect attempt failed, or reconnection gave up.
  connectionFailed,

  /// We were connected and the link dropped — device out of range or
  /// powered off. A bounded reconnect follows.
  disconnected,

  /// A reconnect attempt is in flight after a real drop.
  reconnecting,
}

/// Immutable snapshot of the pairing flow, driven by `BlePairingController`.
class BlePairingState {
  const BlePairingState({
    this.stage = BlePairingStage.idle,
    this.devices = const [],
    this.target,
    this.selectedType = DeviceType.glove,
    this.serviceCount = 0,
    this.errorMessage,
    this.permissionPermanentlyDenied = false,
    this.canPromptToEnableBluetooth = false,
    this.reconnectAttempt = 0,
    this.registeredDevice,
  });

  final BlePairingStage stage;

  /// Devices genuinely seen in the current scan, strongest signal first.
  final List<BleDiscoveredDevice> devices;

  /// The device being connected to / currently connected.
  final BleDiscoveredDevice? target;

  /// Which wearable the user says this is. BLE can't tell us, so it is
  /// asked for explicitly before registration.
  final DeviceType selectedType;

  /// How many GATT services [target] exposed — the evidence that the
  /// connection was real rather than assumed.
  final int serviceCount;

  /// The platform's own error text where it gave us one.
  final String? errorMessage;

  /// True when the permission was denied with "don't ask again", so the
  /// system dialog will never reappear and only app settings can fix it.
  final bool permissionPermanentlyDenied;

  /// Android can turn the adapter on for us; iOS cannot.
  final bool canPromptToEnableBluetooth;

  /// How many automatic reconnects have been tried since the drop.
  final int reconnectAttempt;

  final RegisteredDevice? registeredDevice;

  bool get isScanning => stage == BlePairingStage.scanning;

  bool get isBusy =>
      stage == BlePairingStage.connecting ||
      stage == BlePairingStage.registering ||
      stage == BlePairingStage.reconnecting;

  /// Stages in which we believe we hold a live GATT link.
  bool get holdsConnection =>
      stage == BlePairingStage.connected ||
      stage == BlePairingStage.registering ||
      stage == BlePairingStage.registered;

  BlePairingState copyWith({
    BlePairingStage? stage,
    List<BleDiscoveredDevice>? devices,
    BleDiscoveredDevice? target,
    bool clearTarget = false,
    DeviceType? selectedType,
    int? serviceCount,
    String? errorMessage,
    bool clearError = false,
    bool? permissionPermanentlyDenied,
    bool? canPromptToEnableBluetooth,
    int? reconnectAttempt,
    RegisteredDevice? registeredDevice,
    bool clearRegisteredDevice = false,
  }) {
    return BlePairingState(
      stage: stage ?? this.stage,
      devices: devices ?? this.devices,
      target: clearTarget ? null : (target ?? this.target),
      selectedType: selectedType ?? this.selectedType,
      serviceCount: serviceCount ?? this.serviceCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      permissionPermanentlyDenied: permissionPermanentlyDenied ?? this.permissionPermanentlyDenied,
      canPromptToEnableBluetooth: canPromptToEnableBluetooth ?? this.canPromptToEnableBluetooth,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      registeredDevice: clearRegisteredDevice ? null : (registeredDevice ?? this.registeredDevice),
    );
  }
}
