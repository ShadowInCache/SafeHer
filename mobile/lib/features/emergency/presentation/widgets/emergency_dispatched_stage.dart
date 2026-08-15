import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/emergency_providers.dart';
import '../../../../core/animations/animation_helpers.dart';
import '../../../../core/location/location_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/components/buttons/sa_button.dart';
import '../../../../shared/components/cards/sa_contact_card.dart';
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
    this.location,
    super.key,
  });

  final AsyncValue<List<Contact>> contactsAsync;

  /// Contacts the server confirmed it delivered to. Empty while the
  /// dispatch is still in flight.
  final Set<String> notifiedContactIds;

  /// Null until the dispatch call returns.
  final DispatchResult? dispatchResult;

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
      return ('Sending…', Colors.white.withValues(alpha: 0.5));
    }
    if (result.isQueued) {
      return ('Will send when you have signal', Colors.white.withValues(alpha: 0.5));
    }
    return ('Could not reach', AppColors.warning500);
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
      return 'You are offline. Your alert is saved and will send the moment '
          'you have signal.';
    }
    final total = result.outcome.contactsTotal ?? 0;
    final reached = result.outcome.contactsNotified ?? 0;
    if (total == 0) {
      return 'No emergency contacts are set up, so nobody could be alerted.';
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
              width: 10,
              height: 10,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.coral500),
            ),
            const SizedBox(width: AppSpacing.space2),
            Flexible(
              child: Text(
                'Help is on the way',
                style: AppTypography.headingL.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.space2),
        // Deliberately reports what happened rather than reassuring. The
        // old copy claimed "your contacts have been alerted" the instant
        // the countdown ended, before any request had returned — and at
        // the time, before the backend contacted anyone at all.
        Text(
          _statusLine,
          style: AppTypography.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
        if (_showFallbackWarning) ...[
          const SizedBox(height: AppSpacing.space3),
          _CouldNotReachBanner(),
        ],
        const SizedBox(height: AppSpacing.space5),
        _LiveLocationPanel(location: location),
        const SizedBox(height: AppSpacing.space6),
        Text('Notifying', style: AppTypography.headingS.copyWith(color: Colors.white)),
        const SizedBox(height: AppSpacing.space3),
        contactsAsync.when(
          data: (contacts) => Column(
            children: [
              for (final contact in contacts) ...[
                SaContactCard(
                  name: contact.name,
                  relationship: contact.relationship,
                  priority: contact.priority,
                  confirmed: notifiedContactIds.contains(contact.id),
                ),
                if (_labelFor(contact.id) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.space4, top: 2),
                    child: Text(
                      _labelFor(contact.id)!.$1,
                      style: AppTypography.bodyS.copyWith(color: _labelFor(contact.id)!.$2),
                    ),
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
            style: AppTypography.bodyM.copyWith(color: Colors.white.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        SaButton(
          label: "I'm Safe — Cancel Alert",
          variant: SaButtonVariant.danger,
          confirmRequired: true,
          fullWidth: true,
          onPressed: onMarkSafe,
        ),
      ],
    );
  }
}

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
        color: AppColors.warning500.withValues(alpha: 0.14),
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.warning500.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SaIcon(SaIconGlyph.bell, size: 18, color: AppColors.warning500),
          const SizedBox(width: AppSpacing.space3),
          Expanded(
            child: Text(
              'Nobody could be reached. Call your local emergency number now.',
              style: AppTypography.bodyM.copyWith(color: Colors.white),
            ),
          ),
        ],
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
        color: AppColors.dark800,
        borderRadius: AppRadius.xl2Radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const SaIcon(SaIconGlyph.mapPin, size: 32, color: AppColors.coral500),
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
                        style: AppTypography.headingS.copyWith(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (loc is LocationAvailable) ...[const SizedBox(width: AppSpacing.space2), const _LiveBadge()],
                  ],
                ),
                const SizedBox(height: AppSpacing.space1),
                Text(
                  subtitle,
                  style: AppTypography.monoDataS.copyWith(color: Colors.white.withValues(alpha: 0.6)),
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
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.coral500)),
          const SizedBox(width: AppSpacing.space1),
          Text('LIVE', style: AppTypography.labelM.copyWith(color: AppColors.coral500)),
        ],
      ),
    );
  }
}
