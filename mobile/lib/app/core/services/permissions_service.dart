import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsService {
  static const List<Permission> _allPermissionsMobile = [
    Permission.camera,
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.locationAlways,
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
    Permission.notification,
    Permission.contacts,
    Permission.storage,
    Permission.sms,
    Permission.phone,
  ];

  static const List<Permission> _allPermissionsWeb = [
    Permission.camera,
    Permission.microphone,
    Permission.notification,
  ];

  static const List<Permission> _essentialPermissionsMobile = [
    Permission.camera,
    Permission.microphone,
    Permission.locationWhenInUse,
    Permission.notification,
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ];

  static const List<Permission> _essentialPermissionsWeb = [
    Permission.camera,
    Permission.microphone,
    Permission.notification,
  ];

  List<Permission> get _allPermissions =>
      kIsWeb ? _allPermissionsWeb : _allPermissionsMobile;

  List<Permission> get _essentialPermissions =>
      kIsWeb ? _essentialPermissionsWeb : _essentialPermissionsMobile;

  Future<Map<Permission, PermissionStatus>> requestAll() {
    return _allPermissions.request();
  }

  Future<Map<Permission, PermissionStatus>> requestEssential() {
    return _essentialPermissions.request();
  }

  Future<Map<Permission, PermissionStatus>> checkStatuses() async {
    final statuses = <Permission, PermissionStatus>{};
    for (final permission in _allPermissions) {
      statuses[permission] = await permission.status;
    }
    return statuses;
  }

  Future<bool> hasEssentialPermissions() async {
    final statuses = await requestEssential();
    return statuses.values.every((status) => status.isGranted);
  }
}
