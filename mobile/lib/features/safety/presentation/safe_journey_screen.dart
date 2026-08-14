import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/components/buttons/sa_button.dart';
import '../../../shared/components/cards/sa_card.dart';
import '../../../shared/components/feedback/sa_empty_state.dart';
import '../../../shared/components/feedback/sa_loading_shimmer.dart';
import '../../../shared/components/icons/sa_icon.dart';
import '../../../shared/components/overlays/sa_bottom_sheet.dart';
import '../../../shared/components/overlays/sa_toast.dart';
import '../data/safety_providers.dart';
import '../domain/models/safe_journey.dart';
import 'widgets/start_journey_sheet.dart';

/// Safe Journey — a trip with a deadline, watched by chosen contacts.
///
/// While a journey is active the app posts real GPS breadcrumbs through the
/// backend (see `ActiveJourneyNotifier`). If the deadline passes without an
/// arrival confirmation, the overdue policy runs server-side.
class SafeJourneyScreen extends ConsumerStatefulWidget {
  const SafeJourneyScreen({super.key});

  @override
  ConsumerState<SafeJourneyScreen> createState() => _SafeJourneyScreenState();
}

class _SafeJourneyScreenState extends ConsumerState<SafeJourneyScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Drives the countdown label only — the authoritative deadline lives on
    // the server and is re-checked there before anything escalates.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final config = await showSaBottomSheet<StartJourneyConfig>(
      context,
      builder: (context) => const StartJourneySheet(),
    );
    if (config == null || !mounted) return;

    try {
      await ref.read(activeJourneyNotifierProvider.notifier).start(
        destinationLabel: config.destinationLabel,
        expectedDurationMinutes: config.expectedDurationMinutes,
        checkInIntervalMinutes: config.checkInIntervalMinutes,
        contactIds: config.contactIds,
      );
      if (mounted) {
        showSaToast(context, message: 'Safe Journey started', type: SaToastType.success);
      }
    } catch (_) {
      if (mounted) {
        showSaToast(context, message: "Couldn't start the journey", type: SaToastType.error);
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String successMessage) async {
    try {
      await action();
      if (mounted) showSaToast(context, message: successMessage, type: SaToastType.success);
    } catch (_) {
      if (mounted) {
        showSaToast(context, message: 'That didn\'t go through — try again', type: SaToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final journeyAsync = ref.watch(activeJourneyNotifierProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space2,
                AppSpacing.space2,
                AppSpacing.screenMarginPhone,
                0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const SaIcon(SaIconGlyph.chevronLeft),
                    onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                    tooltip: 'Back',
                  ),
                  Expanded(
                    child: Text(
                      'Safe Journey',
                      style: AppTypography.headingM.copyWith(color: onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: journeyAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.screenMarginPhone),
                  child: SaLoadingShimmer(child: SizedBox(height: 220, width: double.infinity)),
                ),
                error: (_, __) => SaEmptyState(
                  title: "Couldn't load your journey",
                  body: 'Check your connection and try again.',
                  ctaLabel: 'Retry',
                  onCtaTap: () => ref.invalidate(activeJourneyNotifierProvider),
                ),
                data: (journey) => journey == null
                    ? _NoJourneyView(onStart: _start)
                    : _ActiveJourneyView(
                        journey: journey,
                        onCheckIn: () => _run(
                          ref.read(activeJourneyNotifierProvider.notifier).checkIn,
                          'Checked in',
                        ),
                        onArrived: () => _run(
                          ref.read(activeJourneyNotifierProvider.notifier).markArrived,
                          'Arrived safely',
                        ),
                        onCancel: () => _run(
                          ref.read(activeJourneyNotifierProvider.notifier).cancel,
                          'Journey cancelled',
                        ),
                        onEscalate: ref.read(activeJourneyNotifierProvider.notifier).escalate,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoJourneyView extends StatelessWidget {
  const _NoJourneyView({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Center(child: SaIcon(SaIconGlyph.mapPin, size: 56, color: AppColors.violet500)),
          const SizedBox(height: AppSpacing.space5),
          Text(
            'No journey in progress',
            style: AppTypography.headingS.copyWith(color: onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'Start a Safe Journey before you set off. Your chosen contacts can be '
            'notified if you don\'t confirm arriving on time.',
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.65)),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          SaButton(label: 'Start Safe Journey', onPressed: onStart, fullWidth: true),
          const SizedBox(height: AppSpacing.space4),
        ],
      ),
    );
  }
}

class _ActiveJourneyView extends StatelessWidget {
  const _ActiveJourneyView({
    required this.journey,
    required this.onCheckIn,
    required this.onArrived,
    required this.onCancel,
    required this.onEscalate,
  });

  final SafeJourney journey;
  final VoidCallback onCheckIn;
  final VoidCallback onArrived;
  final VoidCallback onCancel;
  final Future<void> Function() onEscalate;

  static String _formatRemaining(Duration remaining) {
    final overdue = remaining.isNegative;
    final value = remaining.abs();
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final text = hours > 0
        ? '${hours}h ${minutes.toString().padLeft(2, '0')}m'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    return overdue ? '$text overdue' : text;
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final now = DateTime.now();
    final remaining = journey.remaining(now);
    final isOverdue = journey.status == JourneyStatus.overdue || remaining.isNegative;

    // The server owns the decision; this just tells it the clock ran out.
    if (journey.hasRunOutOfTime(now)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onEscalate());
    }

    final accent = isOverdue ? AppColors.danger500 : AppColors.success500;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenMarginPhone),
      children: [
        SaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Text(
                    isOverdue ? 'Overdue' : 'Journey active',
                    style: AppTypography.labelL.copyWith(color: accent),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space4),
              Text(
                journey.destinationLabel,
                style: AppTypography.headingM.copyWith(color: onSurface),
              ),
              const SizedBox(height: AppSpacing.space1),
              Text(
                'Destination',
                style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: AppSpacing.space5),
              Text(
                _formatRemaining(remaining),
                style: AppTypography.displayM.copyWith(color: isOverdue ? accent : onSurface),
              ),
              Text(
                isOverdue ? 'past your expected arrival' : 'until expected arrival',
                style: AppTypography.bodyS.copyWith(color: onSurface.withValues(alpha: 0.55)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space4),
        SaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: 'Watching contacts',
                value: journey.contactIds.isEmpty
                    ? 'None selected'
                    : '${journey.contactIds.length} contact${journey.contactIds.length == 1 ? '' : 's'}',
              ),
              _DetailRow(
                label: 'Started',
                value: TimeOfDay.fromDateTime(journey.startedAt.toLocal()).format(context),
              ),
              _DetailRow(
                label: 'Expected by',
                value: TimeOfDay.fromDateTime(journey.expectedArrivalAt.toLocal()).format(context),
              ),
              if (journey.lastCheckInAt != null)
                _DetailRow(
                  label: 'Last check-in',
                  value: TimeOfDay.fromDateTime(journey.lastCheckInAt!.toLocal()).format(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space5),
        SaButton(label: "I've arrived safely", onPressed: onArrived, fullWidth: true),
        const SizedBox(height: AppSpacing.space3),
        SaButton(
          label: 'Check in — still on my way',
          onPressed: onCheckIn,
          variant: SaButtonVariant.secondary,
          fullWidth: true,
        ),
        const SizedBox(height: AppSpacing.space3),
        SaButton(
          label: 'Cancel journey',
          onPressed: onCancel,
          variant: SaButtonVariant.danger,
          confirmRequired: true,
          fullWidth: true,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyM.copyWith(color: onSurface.withValues(alpha: 0.6)),
          ),
          Text(value, style: AppTypography.labelM.copyWith(color: onSurface)),
        ],
      ),
    );
  }
}
