class AppSettings {
  const AppSettings({
    required this.pushNotifications,
    required this.locationSharing,
    required this.biometricLock,
  });

  final bool pushNotifications;
  final bool locationSharing;
  final bool biometricLock;

  AppSettings copyWith({bool? pushNotifications, bool? locationSharing, bool? biometricLock}) {
    return AppSettings(
      pushNotifications: pushNotifications ?? this.pushNotifications,
      locationSharing: locationSharing ?? this.locationSharing,
      biometricLock: biometricLock ?? this.biometricLock,
    );
  }
}
