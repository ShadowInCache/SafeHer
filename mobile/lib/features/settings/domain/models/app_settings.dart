class AppSettings {
  const AppSettings({
    required this.pushNotifications,
    required this.smsNotifications,
    required this.emailNotifications,
    required this.locationSharing,
  });

  final bool pushNotifications;
  final bool smsNotifications;
  final bool emailNotifications;
  final bool locationSharing;

  AppSettings copyWith({
    bool? pushNotifications,
    bool? smsNotifications,
    bool? emailNotifications,
    bool? locationSharing,
  }) {
    return AppSettings(
      pushNotifications: pushNotifications ?? this.pushNotifications,
      smsNotifications: smsNotifications ?? this.smsNotifications,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      locationSharing: locationSharing ?? this.locationSharing,
    );
  }
}
