import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emergency/data/emergency_providers.dart';

/// How long the stand-down action stays in front of her after an automatic
/// alert.
///
/// Mirrors `emergency_dispatch.RETRACTION_PROMPT_SECONDS` on the backend, and
/// `tests/test_incident_retraction.py` pins the two together so they cannot
/// drift apart silently.
///
/// This is a *prompt* duration and not a deadline. The server accepts a
/// retraction whenever it arrives, deliberately: the only thing a cutoff
/// could achieve is withholding a correction she has decided to send. What
/// expires here is the prominent banner, not her ability to take the alert
/// back — the incident stays retractable from its own screen afterwards.
const Duration kAutoSosRetractionPrompt = Duration(seconds: 60);

/// Where a stand-down has got to.
enum AutoSosRetractionStage {
  /// Nothing to offer. The normal state.
  idle,

  /// SafeHer raised an alert by itself and she has not acted on it.
  offered,

  /// She tapped, and the correction is being sent.
  standingDown,

  /// The correction went out.
  retracted,

  /// The correction could not be sent. The alert still stands, and she has to
  /// be told that plainly rather than shown a success.
  failed,
}

/// The automatic alert the app is currently offering to take back.
@immutable
class AutoSosRetractionState {
  const AutoSosRetractionState({
    this.incidentId,
    this.dispatchedAt,
    this.stage = AutoSosRetractionStage.idle,
    this.contactsNotified,
    this.failureMessage,
  });

  final String? incidentId;

  /// When the automatic alert went out, by this device's clock. Drives how
  /// long the banner stays up.
  final DateTime? dispatchedAt;

  final AutoSosRetractionStage stage;

  /// How many of the alarmed contacts the correction reached, once known.
  /// Null while it is still fanning out — which must not read as "nobody".
  final int? contactsNotified;

  /// Why the stand-down failed, for the message she sees.
  final String? failureMessage;

  bool get isOffered => stage == AutoSosRetractionStage.offered;
  bool get isBusy => stage == AutoSosRetractionStage.standingDown;

  AutoSosRetractionState copyWith({
    String? incidentId,
    DateTime? dispatchedAt,
    AutoSosRetractionStage? stage,
    int? contactsNotified,
    String? failureMessage,
  }) => AutoSosRetractionState(
    incidentId: incidentId ?? this.incidentId,
    dispatchedAt: dispatchedAt ?? this.dispatchedAt,
    stage: stage ?? this.stage,
    contactsNotified: contactsNotified ?? this.contactsNotified,
    failureMessage: failureMessage ?? this.failureMessage,
  );
}

/// Holds the one automatic alert she can currently take back, and takes it
/// back when she asks.
///
/// **Why this is a provider and not widget state.** Auto-SOS is decided on
/// the server, in the response to a reading the threat pipeline posted in the
/// background. There may be no SafeHer screen on top when it happens — the
/// phone could be in a pocket with the app behind a lock screen. So the fact
/// that an automatic alert went out has to live somewhere a widget can find
/// when it is next drawn, rather than being delivered to whatever happened to
/// be mounted at the time. Same reasoning as `JourneyDetectionStatus`.
///
/// Written by the pipeline, read by the banner.
class AutoSosRetractionNotifier extends Notifier<AutoSosRetractionState> {
  @override
  AutoSosRetractionState build() => const AutoSosRetractionState();

  /// The server raised an alarm by itself. Offer to take it back.
  ///
  /// A second automatic alert replaces the first. Keeping a queue would mean
  /// showing her a stand-down for an older incident while a newer one stands
  /// — and the newer one is the one that just alarmed her contacts.
  void noticeDispatch(String incidentId, {DateTime? at}) {
    state = AutoSosRetractionState(
      incidentId: incidentId,
      dispatchedAt: at ?? DateTime.now(),
      stage: AutoSosRetractionStage.offered,
    );
  }

  /// Stand the alert down and have her contacts told she is safe.
  ///
  /// Guarded against a second tap while the first is in flight. The server is
  /// idempotent, so a double send would not message anyone twice, but a
  /// second request would still race the first one's result back into
  /// [state].
  Future<void> retract() async {
    final incidentId = state.incidentId;
    if (incidentId == null || state.isBusy) return;

    state = state.copyWith(
      stage: AutoSosRetractionStage.standingDown,
      failureMessage: null,
    );
    try {
      final outcome =
          await ref.read(emergencyRepositoryProvider).retractAlert(incidentId);
      state = state.copyWith(
        stage: AutoSosRetractionStage.retracted,
        contactsNotified: outcome.contactsNotified,
      );
    } catch (error) {
      // Back to `offered`, not `failed`-and-gone: the alert is still standing,
      // so the action she needs has to remain available. Telling her it could
      // not be sent while removing the only way to send it would be the worst
      // of both.
      state = state.copyWith(
        stage: AutoSosRetractionStage.failed,
        failureMessage: 'Could not reach SafeHer to cancel. $error',
      );
    }
  }

  /// She acknowledged the alert, or the prompt timed out. Clears the offer
  /// without touching the incident — a dismissed prompt is not a retraction.
  void dismiss() => state = const AutoSosRetractionState();

  /// Lets her try again after a failure.
  void retryable() {
    if (state.stage == AutoSosRetractionStage.failed) {
      state = state.copyWith(stage: AutoSosRetractionStage.offered);
    }
  }
}

final autoSosRetractionProvider =
    NotifierProvider<AutoSosRetractionNotifier, AutoSosRetractionState>(
  AutoSosRetractionNotifier.new,
);
