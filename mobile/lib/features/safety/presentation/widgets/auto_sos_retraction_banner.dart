import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auto_sos_retraction.dart';

/// The way back from an alert SafeHer raised by itself.
///
/// ## Why this is mounted above the router
///
/// Auto-SOS is decided on the server, inside the response to a background
/// reading. There is no guarantee any particular SafeHer screen is on top
/// when it happens — the phone may be in a pocket. So the prompt has to be
/// reachable from wherever she is, which is the same reason
/// `SafetyTriggerListener` lives up here.
///
/// ## Why it is a banner and not a countdown
///
/// The alert has *already gone out*. Auto-SOS has no cancellable countdown in
/// front of it, deliberately: the situations it exists for are the ones where
/// she cannot reach the screen, so a confirmation step would withhold the
/// alert exactly when it is needed. This banner is therefore a correction,
/// not a cancellation, and it must not pretend otherwise — the wording says
/// her contacts were told, because they were.
///
/// The timer on the "offered" state hides the banner, not the ability to
/// retract. The server accepts a stand-down whenever it arrives.
class AutoSosRetractionBanner extends ConsumerStatefulWidget {
  const AutoSosRetractionBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AutoSosRetractionBanner> createState() =>
      _AutoSosRetractionBannerState();
}

class _AutoSosRetractionBannerState
    extends ConsumerState<AutoSosRetractionBanner> {
  Timer? _ticker;

  /// Rebuilds once a second so the remaining time counts down, and retires
  /// the banner when the prompt window closes.
  ///
  /// Only runs while something is on screen — a ticker left running behind an
  /// idle app would wake the UI thread every second for nothing.
  void _syncTicker(AutoSosRetractionState state) {
    final wanted = state.stage == AutoSosRetractionStage.offered;
    if (wanted && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!wanted && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remaining(AutoSosRetractionState state) {
    final at = state.dispatchedAt;
    if (at == null) return Duration.zero;
    final left = kAutoSosRetractionPrompt - DateTime.now().difference(at);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(autoSosRetractionProvider);
    _syncTicker(state);

    final banner = _bannerFor(state);
    return Stack(
      children: [
        widget.child,
        if (banner != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: banner,
              ),
            ),
          ),
      ],
    );
  }

  Widget? _bannerFor(AutoSosRetractionState state) {
    switch (state.stage) {
      case AutoSosRetractionStage.idle:
        return null;

      case AutoSosRetractionStage.offered:
        final left = _remaining(state);
        if (left == Duration.zero) {
          // The window has closed. Retire the banner after this frame rather
          // than during build, which must not mutate providers.
          scheduleMicrotask(() {
            if (mounted) {
              ref.read(autoSosRetractionProvider.notifier).dismiss();
            }
          });
          return null;
        }
        return _Shell(
          tone: _Tone.alarm,
          icon: Icons.campaign_outlined,
          title: 'SafeHer alerted your contacts',
          // Not "are you ok?" — the alert has already been sent, and a
          // question implies it has not. She needs to know what happened and
          // what she can do about it.
          message: 'It did this automatically, from your sensors. '
              'If you are safe, let them know.',
          action: FilledButton.icon(
            onPressed: () =>
                ref.read(autoSosRetractionProvider.notifier).retract(),
            icon: const Icon(Icons.check),
            // Rounded up, not truncated. `inSeconds` floors, so the very
            // first frame of a 60-second window would read "59s" — a counter
            // that starts by appearing to have already lost a second.
            label: Text("I'm safe (${(left.inMilliseconds / 1000).ceil()}s)"),
          ),
          onDismiss: () =>
              ref.read(autoSosRetractionProvider.notifier).dismiss(),
        );

      case AutoSosRetractionStage.standingDown:
        return const _Shell(
          tone: _Tone.busy,
          icon: Icons.outgoing_mail,
          title: 'Telling your contacts',
          message: 'Sending them a false-alarm message.',
          action: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );

      case AutoSosRetractionStage.retracted:
        final count = state.contactsNotified;
        return _Shell(
          tone: _Tone.resolved,
          icon: Icons.check_circle_outline,
          title: 'False alarm sent',
          // The count is omitted rather than guessed when the server has not
          // finished its own fan-out. "0 contacts" would be a lie told in the
          // one direction that matters.
          message: count == null
              ? 'Your contacts are being told you are safe.'
              : 'Told $count ${count == 1 ? 'contact' : 'contacts'} you are safe.',
          action: TextButton(
            onPressed: () =>
                ref.read(autoSosRetractionProvider.notifier).dismiss(),
            child: const Text('Done'),
          ),
        );

      case AutoSosRetractionStage.failed:
        return _Shell(
          tone: _Tone.alarm,
          icon: Icons.error_outline,
          title: 'Could not cancel',
          // Says plainly that the alert still stands. Showing a soft failure
          // here would leave her believing her contacts had been corrected
          // when they had not.
          message: 'Your contacts still think you need help. '
              '${state.failureMessage ?? ''}'.trim(),
          action: FilledButton(
            onPressed: () {
              ref.read(autoSosRetractionProvider.notifier).retryable();
              ref.read(autoSosRetractionProvider.notifier).retract();
            },
            child: const Text('Try again'),
          ),
        );
    }
  }
}

enum _Tone { alarm, busy, resolved }

class _Shell extends StatelessWidget {
  const _Shell({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    this.onDismiss,
  });

  final _Tone tone;
  final IconData icon;
  final String title;
  final String message;
  final Widget action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _Tone.alarm => (scheme.errorContainer, scheme.onErrorContainer),
      _Tone.busy => (scheme.surfaceContainerHighest, scheme.onSurface),
      _Tone.resolved => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    icon: Icon(Icons.close, size: 18, color: foreground),
                    tooltip: 'Hide',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground,
              ),
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ),
      ),
    );
  }
}
