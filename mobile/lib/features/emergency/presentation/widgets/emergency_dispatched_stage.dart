import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/emergency_providers.dart';
import '../../domain/models/evidence_state.dart';
import '../../../../core/animations/animation_helpers.dart';
import '../../../../core/location/location_result.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/platform/external_actions.dart';
import '../../../../shared/components/overlays/sa_toast.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/icons/sa_icon.dart';
import '../../../contacts/domain/models/contact.dart';

/// Stage 3 — the alert has been sent. Shows a live-location panel (real
/// coordinates when a fix was acquired, a plain-language fallback
/// otherwise) and staggers each contact from "Notifying…" to "Notified"
/// as [notifiedContactIds] grows.
class EmergencyDispatchedStage extends StatelessWidget {
  const EmergencyDispatchedStage({
    required this.contactsAsync,
    required this.notifiedContactIds,
    required this.onMarkSafe,
    this.dispatchResult,
    this.evidence = EvidenceState.idle,
    this.hasVideo = false,
    this.hasGlassesAudio = false,
    this.location,
    super.key,
  });

  final AsyncValue<List<Contact>> contactsAsync;

  /// Contacts the server confirmed it delivered to. Empty while the
  /// dispatch is still in flight.
  final Set<String> notifiedContactIds;

  /// Null until the dispatch call returns.
  final DispatchResult? dispatchResult;

  final EvidenceState evidence;

  /// True when the camera opened alongside the microphone.
  final bool hasVideo;

  /// Whether the glasses' microphone is also recording.
  ///
  /// A second vantage point, not a replacement: the phone's recording is the
  /// one that always exists, and this one is on her head rather than in a bag.
  final bool hasGlassesAudio;

  final VoidCallback onMarkSafe;
  final LocationResult? location;

  /// Per-contact status line, or null when the contact was reached and the
  /// card's own confirmed tick already says so.
  ///
  /// Three states, deliberately kept apart: still sending, saved for later
  /// because we are offline, and genuinely failed. Collapsing the first two
  /// into "could not reach" would panic a user whose alert is simply queued;
  /// collapsing the third into "sending…" would do the opposite, which is
  /// worse.
  (String, Color)? _labelFor(String contactId) {
    if (notifiedContactIds.contains(contactId)) return null;

    final result = dispatchResult;
    if (result == null) {
      return ('Sending…', _onFieldMuted);
    }
    if (result.isQueued) {
      return switch (result.queueReason) {
        QueueReason.offline => (
          'Will send when you have signal',
          _onFieldMuted,
        ),
        // The phone has a network; SafeHer just could not be reached. Saying
        // "when you have signal" here told a woman with five bars to wait for
        // something she already had.
        _ => ('Retrying…', _onFieldMuted),
      };
    }
    // The server answers before it has finished contacting anyone. Until it
    // says it is done, a contact that is not yet reached is still being
    // tried — calling that "Could not reach" is the same false report in the
    // opposite direction.
    if (!result.outcome.progress.isSettled) {
      return ('Sending…', _onFieldMuted);
    }
    return ('Could not reach', _onFieldAlarm);
  }

  bool get _showFallbackWarning {
    final result = dispatchResult;
    if (result == null || result.isQueued) return false;
    return result.outcome.reachedNobody;
  }

  String get _statusLine {
    final result = dispatchResult;
    if (result == null) return 'Alerting your emergency contacts…';

    if (result.isQueued) {
      return switch (result.queueReason) {
        QueueReason.offline =>
          'You are offline. Your alert is saved and will send the moment you '
              'have signal.',
        // Deliberately does not claim the alert failed *or* that it was
        // delivered. Neither is known: the request did not come back, which
        // is not the same as it not arriving. It says what SafeHer is doing
        // and what she can do that does not depend on us.
        _ =>
          'Your alert is saved and SafeHer is still trying to send it. If you '
              'need help now, call your emergency number.',
      };
    }

    final total = result.outcome.contactsTotal ?? 0;
    final reached = result.outcome.contactsNotified ?? 0;

    if (total == 0) {
      return 'No emergency contacts are set up, so nobody could be alerted.';
    }

    // Still fanning out. Reporting a final count here would be a guess that
    // gets more wrong the more contacts there are.
    if (!result.outcome.progress.isSettled) {
      return reached == 0
          ? 'Alerting your $total emergency contacts…'
          : '$reached of $total alerted so far…';
    }

    if (reached == 0) return 'Your alert could not be delivered to anyone.';
    if (reached == total) {
      return reached == 1
          ? 'Your emergency contact has been alerted.'
          : 'All $reached emergency contacts have been alerted.';
    }
    return '$reached of $total emergency contacts alerted.';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenMarginPhone,
        AppSpacing.space4,
        AppSpacing.screenMarginPhone,
        AppSpacing.space8,
      ),
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.neutral50),
            ),
            const SizedBox(width: AppSpacing.space2),
            Text(
              'ALERT SENT',
              style: AppTypography.labelM.copyWith(
                color: AppColors.neutral50,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space4),
        // Deliberately unclamped: this is the one headline in the app that
        // should be readable at arm's length, so it wraps rather than
        // ellipsising, and the ListView takes the height.
        Text(
          'Help is on the way',
          style: AppTypography.displayCondensed.copyWith(color: AppColors.neutral50),
        ),
        const SizedBox(height: AppSpacing.space2),
        // Deliberately reports what happened rather than reassuring. The
        // old copy claimed "your contacts have been alerted" the instant
        // the countdown ended, before any request had returned — and at
        // the time, before the backend contacted anyone at all.
        Text(
          _statusLine,
          style: AppTypography.bodyL.copyWith(
            color: AppColors.neutral50.withValues(alpha: 0.85),
          ),
        ),
        if (_showFallbackWarning) ...[
          const SizedBox(height: AppSpacing.space3),
          _CouldNotReachBanner(),
        ],
        const SizedBox(height: AppSpacing.space5),
        const _CallHelplineButton(),
        const SizedBox(height: AppSpacing.space3),
        _EvidencePanel(
          state: evidence,
          hasVideo: hasVideo,
          hasGlassesAudio: hasGlassesAudio,
        ),
        const SizedBox(height: AppSpacing.space3),
        _LiveLocationPanel(location: location),
        const SizedBox(height: AppSpacing.space6),
        Text(
          'NOTIFYING',
          style: AppTypography.labelM.copyWith(
            color: _onFieldMuted,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        contactsAsync.when(
          data: (contacts) => Column(
            children: [
              for (final contact in contacts) ...[
                // Plain rows rather than SaContactCard. That card paints a
                // surface fill, which on the emergency field reads as a piece
                // of another screen pasted onto this one — and it leads with a
                // priority badge, which is not what you need to know once the
                // alert is already out. What matters here is who, and whether
                // they have it.
                _NotifiedContactRow(
                  name: contact.name,
                  relationship: contact.relationship,
                  reached: notifiedContactIds.contains(contact.id),
                  pending: _labelFor(contact.id),
                ),
                const SizedBox(height: AppSpacing.space3),
              ],
            ],
          ),
          loading: () => const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, stackTrace) => Text(
            "Couldn't load emergency contacts.",
            style: AppTypography.bodyM.copyWith(color: _onFieldMuted),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SaButton(
          label: "I'm Safe — Cancel Alert",
          variant: SaButtonVariant.inverseOutline,
          confirmRequired: true,
          fullWidth: true,
          onPressed: onMarkSafe,
        ),
      ],
    );
  }
}

/// One emergency contact, and whether the alert actually reached them.
///
/// Every row states an outcome. A spinner with no verdict is the one thing
/// this screen must never show: a woman who cannot tell "still trying" from
/// "nobody came" will make the wrong decision about what to do next.
class _NotifiedContactRow extends StatelessWidget {
  const _NotifiedContactRow({
    required this.name,
    required this.relationship,
    required this.reached,
    required this.pending,
  });

  final String name;
  final String relationship;
  final bool reached;

  /// `(label, colour)` while the outcome is not yet settled; null once it is.
  final (String, Color)? pending;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final (String label, Color colour) = reached
        ? ('ALERTED', _onField)
        : (pending ?? ('Could not reach', _onFieldAlarm));

    return Semantics(
      label: '$name, $relationship, $label',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _onField.withValues(alpha: 0.45)),
              ),
              child: Text(
                initial,
                style: AppTypography.labelL.copyWith(color: _onField),
              ),
            ),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: AppTypography.headingS.copyWith(color: _onField),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    relationship,
                    style: AppTypography.bodyS.copyWith(color: _onFieldMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.space2),
            if (reached) ...[
              const SaIcon(SaIconGlyph.check, size: 15, color: _onField),
              const SizedBox(width: AppSpacing.space1),
            ],
            // "ALERTED" is a token and takes the stamped treatment; "Sending…"
            // and "Could not reach" are sentences, and letterspaced bold on a
            // sentence reads like shouting rather than like a status.
            Text(
              label,
              style: reached
                  ? AppTypography.labelM.copyWith(
                      color: colour,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    )
                  : AppTypography.bodyS.copyWith(color: colour),
            ),
          ],
        ),
      ),
    );
  }
}

/// The only three inks that survive on [AppColors.emergencyField]. Anything
/// tinted — coral, violet, the semantic green — sits too close to the ground
/// to register as a separate colour at all.
const _onField = AppColors.neutral50;
const _onFieldMuted = Color(0xB3FAF8F4); // paper at 70%
const _onFieldAlarm = Color(0xFFF5C77E); // light ochre, 4.0:1 on the field

/// Shown when the alert reached nobody. On this screen the worst outcome is
/// a user who believes help is coming and stops trying, so this is loud and
/// tells her what to do instead.
class _CouldNotReachBanner extends StatelessWidget {
  const _CouldNotReachBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: _onFieldAlarm.withValues(alpha: 0.16),
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: _onFieldAlarm.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SaIcon(SaIconGlyph.bell, size: 18, color: _onFieldAlarm),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              'Nobody could be reached. Call your local emergency number now.',
              style: AppTypography.bodyM.copyWith(color: _onFieldAlarm),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says what happened to the recording. A silent failure would leave the
/// user believing evidence exists when none does — which matters later,
/// when it is the difference between a report that stands up and one that
/// does not.
class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.state,
    this.hasVideo = false,
    this.hasGlassesAudio = false,
  });

  final EvidenceState state;

  /// Whether the camera also opened. Audio is the recording that works
  /// wherever the phone is; video is a bonus when the lens happened to be
  /// pointed at something, so it qualifies the message rather than
  /// replacing it.
  final bool hasVideo;
  final bool hasGlassesAudio;

  /// Names every source actually capturing, so the sentence describes what
  /// is happening rather than what the feature is capable of.
  String get _sources {
    if (hasVideo && hasGlassesAudio) return 'audio, video and camera audio';
    if (hasVideo) return 'audio and video';
    if (hasGlassesAudio) return 'audio from your phone and camera';
    return 'audio';
  }

  @override
  Widget build(BuildContext context) {
    if (state == EvidenceState.idle) return const SizedBox.shrink();

    final (String message, Color color) = switch (state) {
      EvidenceState.recording => ('Recording $_sources evidence', _onField),
      EvidenceState.uploading => ('Saving evidence securely…', _onField),
      EvidenceState.saved => (
        hasVideo || hasGlassesAudio
            ? 'Evidence saved and encrypted — $_sources'
            : 'Evidence saved and encrypted',
        _onField,
      ),
      EvidenceState.uploadFailed => (
        'Evidence recorded but not uploaded — it will be lost',
        _onFieldAlarm,
      ),
      EvidenceState.unavailable => (
        'No audio evidence — microphone unavailable',
        _onFieldAlarm,
      ),
      EvidenceState.unsupported => (
        'Audio evidence needs the SafeHer app on your phone',
        _onFieldAlarm,
      ),
      EvidenceState.discarded => ('Evidence discarded', _onFieldMuted),
      EvidenceState.idle => ('', _onFieldMuted),
    };

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.space3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadius.mdRadius,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            if (state.isActive)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              SaIcon(SaIconGlyph.mic, size: 16, color: color),
            const SizedBox(width: AppSpacing.space3),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyM.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveLocationPanel extends StatelessWidget {
  const _LiveLocationPanel({this.location});

  final LocationResult? location;

  @override
  Widget build(BuildContext context) {
    final loc = location;
    final subtitle = switch (loc) {
      LocationAvailable() =>
        '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)} (±${loc.accuracyMeters.round()}m)',
      LocationUnavailable() => loc.userMessage,
      null => 'Acquiring your location…',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.space4),
      decoration: BoxDecoration(
        color: _onField.withValues(alpha: 0.10),
        borderRadius: AppRadius.xl2Radius,
        border: Border.all(color: _onField.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const SaIcon(SaIconGlyph.mapPin, size: 32, color: AppColors.neutral50),
          const SizedBox(width: AppSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Sharing live location',
                        style: AppTypography.headingS.copyWith(color: _onField),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (loc is LocationAvailable) ...[const SizedBox(width: AppSpacing.space2), const _LiveBadge()],
                  ],
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  subtitle,
                  style: AppTypography.monoDataS.copyWith(color: _onFieldMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A pulsing "LIVE" badge — dot + label opacity breathing 1.0↔0.3 on a
/// 1s loop, snapping to fully-on under reduced motion.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AnimationHelpers.repeat(context, _controller, reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.3).animate(_controller),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: _onField)),
          const SizedBox(width: AppSpacing.space1),
          Text('LIVE', style: AppTypography.labelM.copyWith(color: _onField)),
        ],
      ),
    );
  }
}

/// One tap to the national emergency number.
///
/// **Why this is a button and not an automatic call.** Android will not let
/// an app place a call to an emergency number: `ACTION_CALL` is refused for
/// them and only `ACTION_DIAL` — which fills the dialler and waits for a
/// human to press call — is permitted. That restriction is the operating
/// system's, not a policy we could ask to be excepted from, and it exists
/// because automatic calls to emergency services from software have a long
/// history of flooding them.
///
/// It is right anyway. Detection models can be wrong, and an app that dialled
/// 112 by itself on a false positive would spend an emergency operator's time
/// on someone who is fine — and teach that user to disable the feature before
/// the day it matters. So SafeHer gets her one tap away and leaves the tap to
/// her.
class _CallHelplineButton extends StatelessWidget {
  const _CallHelplineButton();

  /// Matches how the rest of the app reaches the dialler — a const instance
  /// rather than a provider, since it holds no state.
  static const _actions = ExternalActions();

  @override
  Widget build(BuildContext context) {
    final number = AppConfig.emergencyHelplineNumber;

    return SaButton(
      label: 'Call $number',
      variant: SaButtonVariant.inverse,
      fullWidth: true,
      semanticsLabel: 'Call the emergency helpline on $number',
      onPressed: () async {
        final launched = await _actions.dial(number);
        if (!context.mounted || launched) return;
        // Never fails silently. A button that appears to do nothing during an
        // emergency is worse than one that is not offered.
        showSaToast(
          context,
          message: 'Could not open the dialler. Call $number yourself.',
          type: SaToastType.error,
        );
      },
    );
  }
}
