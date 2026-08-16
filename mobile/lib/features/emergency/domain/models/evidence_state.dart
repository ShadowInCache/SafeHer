/// What happened to the evidence recording for this emergency.
///
/// Reported to the user rather than kept internal. "Evidence is being
/// recorded" changes what she does next — and so does its absence, which is
/// why a failure has its own state instead of silently looking like nothing
/// was ever attempted.
enum EvidenceState {
  /// No emergency in progress.
  idle,

  /// Capturing audio now.
  recording,

  /// Recording finished, upload in flight.
  uploading,

  /// Stored on the server, encrypted.
  saved,

  /// Captured but could not be sent. The alert still went out.
  uploadFailed,

  /// Nothing was captured — permission refused, or no microphone.
  unavailable,

  /// This platform cannot record at all (a browser).
  unsupported,

  /// Deliberately deleted: the user marked herself safe, or the alert was
  /// queued offline and had no incident to attach to.
  discarded;

  bool get isActive => this == recording || this == uploading;
}
