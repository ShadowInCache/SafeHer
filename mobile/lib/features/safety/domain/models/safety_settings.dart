/// Opt-in configuration for the phone-side safety triggers.
///
/// Everything that can raise an alarm defaults to off. A trigger the user
/// never switched on must never fire — that is the whole reason these live on
/// the server next to the account rather than in device preferences.
class SafetyPreferences {
  const SafetyPreferences({
    required this.shakeTriggerEnabled,
    required this.shakeSensitivity,
    required this.voiceCommandsEnabled,
    required this.requirePinToCancel,
    required this.journeyAutoShareLocation,
  });

  const SafetyPreferences.defaults()
    : shakeTriggerEnabled = false,
      shakeSensitivity = 2,
      voiceCommandsEnabled = false,
      requirePinToCancel = false,
      journeyAutoShareLocation = true;

  final bool shakeTriggerEnabled;

  /// 1 = least sensitive (hardest to trigger), 3 = most sensitive.
  final int shakeSensitivity;
  final bool voiceCommandsEnabled;
  final bool requirePinToCancel;
  final bool journeyAutoShareLocation;

  SafetyPreferences copyWith({
    bool? shakeTriggerEnabled,
    int? shakeSensitivity,
    bool? voiceCommandsEnabled,
    bool? requirePinToCancel,
    bool? journeyAutoShareLocation,
  }) => SafetyPreferences(
    shakeTriggerEnabled: shakeTriggerEnabled ?? this.shakeTriggerEnabled,
    shakeSensitivity: shakeSensitivity ?? this.shakeSensitivity,
    voiceCommandsEnabled: voiceCommandsEnabled ?? this.voiceCommandsEnabled,
    requirePinToCancel: requirePinToCancel ?? this.requirePinToCancel,
    journeyAutoShareLocation: journeyAutoShareLocation ?? this.journeyAutoShareLocation,
  );
}

/// Whether a cancel PIN exists, and whether too many wrong attempts have
/// temporarily locked it. The PIN itself never leaves the server.
class SafetyPinStatus {
  const SafetyPinStatus({required this.isSet, this.isLocked = false, this.lockedUntil});

  final bool isSet;
  final bool isLocked;
  final DateTime? lockedUntil;
}

/// Result of checking a PIN during an active SOS countdown.
class PinVerificationResult {
  const PinVerificationResult({required this.valid, this.attemptsRemaining, this.lockedUntil});

  final bool valid;
  final int? attemptsRemaining;
  final DateTime? lockedUntil;
}
