/// The fixed set of things the voice layer is allowed to do.
///
/// This is an allow-list on purpose. Speech recognition misfires, and an
/// open-ended "do what the sentence says" layer wired into an emergency
/// system is a way to dispatch an alert nobody asked for — or worse, to
/// cancel one somebody urgently needed.
enum VoiceCommand {
  /// Opens the SOS screen with its countdown running. Never dispatches
  /// immediately — the countdown is the confirmation step.
  startSos,

  /// Only *requests* cancellation. If the user has "require PIN to cancel"
  /// on, the PIN prompt still stands between this and a cancelled alert,
  /// because a voice anyone nearby can imitate must not silence an alarm.
  cancelSos,

  callPrimaryContact,
  shareLocation,
  startJourney,
  showNearbyHelp;

  String get spokenExample => switch (this) {
    VoiceCommand.startSos => '"help me" / "start SOS"',
    VoiceCommand.cancelSos => '"cancel SOS"',
    VoiceCommand.callPrimaryContact => '"call my emergency contact"',
    VoiceCommand.shareLocation => '"share my location"',
    VoiceCommand.startJourney => '"start safe journey"',
    VoiceCommand.showNearbyHelp => '"find help nearby"',
  };

  String get label => switch (this) {
    VoiceCommand.startSos => 'Start SOS',
    VoiceCommand.cancelSos => 'Cancel SOS',
    VoiceCommand.callPrimaryContact => 'Call emergency contact',
    VoiceCommand.shareLocation => 'Share location',
    VoiceCommand.startJourney => 'Start Safe Journey',
    VoiceCommand.showNearbyHelp => 'Find help nearby',
  };
}

/// Maps recognised speech onto [VoiceCommand]s.
///
/// Kept as a pure function with no plugin dependency so the matching rules
/// are directly testable without a microphone.
class VoiceCommandMatcher {
  const VoiceCommandMatcher();

  static const _phrases = <VoiceCommand, List<String>>{
    // "help me" is intentionally the only bare-"help" variant that counts;
    // "help" alone appears in far too much ordinary speech.
    VoiceCommand.startSos: ['help me', 'start sos', 'trigger sos', 'send sos', 'emergency now'],
    VoiceCommand.cancelSos: ['cancel sos', 'stop sos', 'cancel emergency', 'false alarm'],
    VoiceCommand.callPrimaryContact: [
      'call my emergency contact',
      'call emergency contact',
      'call my contact',
    ],
    VoiceCommand.shareLocation: ['share my location', 'send my location', 'share location'],
    VoiceCommand.startJourney: ['start safe journey', 'start journey', 'begin safe journey'],
    VoiceCommand.showNearbyHelp: ['find help nearby', 'nearby help', 'find police', 'nearest hospital'],
  };

  /// Returns the matched command, or null when nothing matched confidently.
  ///
  /// Cancellation is matched before activation: if a phrase somehow contains
  /// both, the safer reading is that the user is trying to stand an alert
  /// down, and cancelling still has to pass the PIN gate anyway.
  VoiceCommand? match(String recognisedText) {
    // Punctuation becomes a space, then runs of whitespace collapse to one —
    // otherwise "Cancel, SOS." normalises to "cancel  sos" and fails to match
    // the "cancel sos" phrase.
    final normalised = recognisedText
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalised.isEmpty) return null;

    final ordered = [
      VoiceCommand.cancelSos,
      VoiceCommand.startSos,
      VoiceCommand.callPrimaryContact,
      VoiceCommand.shareLocation,
      VoiceCommand.startJourney,
      VoiceCommand.showNearbyHelp,
    ];

    for (final command in ordered) {
      for (final phrase in _phrases[command]!) {
        if (normalised.contains(phrase)) return command;
      }
    }
    return null;
  }

  List<String> phrasesFor(VoiceCommand command) => List.unmodifiable(_phrases[command]!);
}
