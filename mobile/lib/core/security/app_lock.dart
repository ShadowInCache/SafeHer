import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_providers.dart';
import '../router/app_router.dart';
import '../biometrics/biometric_providers.dart';
import '../biometrics/biometric_service.dart';
import '../local/app_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/theme_extensions.dart';
import '../../shared/components/buttons/sa_button.dart';
import '../../shared/components/icons/sa_icon.dart';

/// Holds the app behind a biometric prompt when the user has asked for one.
///
/// **The bug this fixes.** Profile > Security > Biometric Unlock prompted for
/// a fingerprint once, wrote `biometricEnabled = true`, and was then read by
/// exactly one place: the toggle itself, to draw its own switch. Nothing ever
/// consulted it again. The setting looked like protection and was decoration
/// -- the same failure the threat-threshold slider is careful to warn about.
///
/// **Two decisions worth stating, because both cut against the usual advice
/// for an app lock.**
///
/// *The lock never covers SOS.* The threat it defends against is someone
/// picking up an unlocked phone and reading incident history, saved contacts,
/// or recorded evidence. Somebody triggering an SOS they do not own is not
/// that threat -- it summons help. Putting a fingerprint between a frightened
/// person and the alarm, when fingerprints fail routinely on wet or shaking
/// hands, trades a real safety outcome for a theoretical one. So the lock
/// screen carries its own emergency route out.
///
/// *It fails open, not closed.* If biometrics stop being available -- the
/// user removed their enrolment, changed phones, the sensor broke -- the app
/// unlocks and turns the setting off rather than sealing itself. `local_auth`
/// with `biometricOnly` offers no way back in, so failing closed here means a
/// safety app that can never be opened again. The device credential is
/// offered as a fallback for the same reason.
class AppLock extends ConsumerStatefulWidget {
  const AppLock({required this.child, super.key});

  final Widget child;

  /// How long the app may sit in the background before it re-locks.
  ///
  /// Zero would re-prompt when the user glances at a notification or picks a
  /// photo, which trains people to switch the feature off. Long enough to
  /// survive an app switch, short enough that a handed-over phone locks.
  static const backgroundGrace = Duration(seconds: 30);

  @override
  ConsumerState<AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<AppLock> with WidgetsBindingObserver {
  bool _locked = false;
  bool _prompting = false;
  DateTime? _backgroundedAt;
  String? _message;

  /// True while the user has stepped past the lock to reach the emergency
  /// screen. It suspends the overlay for that route only -- the moment they
  /// navigate anywhere else the lock comes straight back, so "Emergency SOS"
  /// is a door into the alarm and not a way around the lock.
  bool _emergencyBypass = false;
  VoidCallback? _routeListener;

  /// Held directly rather than re-read in [dispose]: `ref` is unusable once
  /// the widget is disposed, so looking the router up there to detach the
  /// listener throws instead of cleaning up.
  RouterDelegate<Object>? _routerDelegate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A cold start is the clearest case for locking: the phone may have
    // changed hands since the app was last open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lockIfEnabled();
      _watchRoutes();
    });
  }

  void _watchRoutes() {
    if (!mounted) return;
    final router = ref.read(appRouterProvider);
    void onRouteChanged() {
      if (!mounted || !_emergencyBypass) return;
      final location = router.routerDelegate.currentConfiguration.uri.path;
      if (location.startsWith('/emergency')) return;
      // Left the emergency screen -- the reason for the bypass is gone.
      setState(() {
        _emergencyBypass = false;
        _locked = true;
      });
      unawaited(_unlock());
    }

    _routeListener = onRouteChanged;
    _routerDelegate = router.routerDelegate;
    _routerDelegate!.addListener(onRouteChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final listener = _routeListener;
    if (listener != null) _routerDelegate?.removeListener(listener);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null) return;
    if (DateTime.now().difference(since) < AppLock.backgroundGrace) return;
    unawaited(_lockIfEnabled());
  }

  Future<void> _lockIfEnabled() async {
    if (_locked || !mounted) return;
    if (!ref.read(appPreferencesProvider).biometricEnabled) return;

    // Nothing to protect when nobody is signed in, and locking the login
    // screen would strand a user who cannot get past it.
    final signedIn = await ref.read(authRepositoryProvider).hasActiveSession();
    if (!signedIn || !mounted) return;

    setState(() => _locked = true);
    unawaited(_unlock());
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    try {
      final biometrics = ref.read(biometricServiceProvider);

      // Fail open rather than seal the app shut -- see the class doc.
      if (!await biometrics.isAvailable || !await biometrics.hasEnrolledBiometrics) {
        await ref.read(appPreferencesProvider).setBiometricEnabled(false);
        if (!mounted) return;
        ref.invalidate(appPreferencesProvider);
        setState(() {
          _locked = false;
          _message = null;
        });
        return;
      }

      final result = await biometrics.authenticate(
        reason: 'Unlock SafeHer',
        allowDeviceCredential: true,
      );
      if (!mounted) return;
      setState(() {
        if (result is BiometricSuccess) {
          _locked = false;
          _message = null;
        } else if (result is BiometricRejected) {
          _message = result.userMessage(biometrics.platformLabel);
        }
      });
    } finally {
      _prompting = false;
    }
  }

  /// Steps past the lock to the emergency screen, and only that screen.
  void _openEmergency() {
    setState(() => _emergencyBypass = true);
    ref.read(appRouterProvider).go('/emergency');
  }

  @override
  Widget build(BuildContext context) {
    // The app stays mounted underneath: tearing it down would drop live
    // monitoring and any in-flight dispatch, and the lock is about what can
    // be *seen*, not about stopping the app from doing its job.
    final showLock = _locked && !_emergencyBypass;
    return Stack(
      children: [
        // Painting an opaque screen over the app hides it from eyes and
        // nothing else: the widgets underneath stay in the tree, so a screen
        // reader would happily read out the contact names and incident titles
        // the lock is there to cover, and a stray tap could still land on
        // them. Excluding semantics and ignoring pointers is what actually
        // makes the lock a lock.
        ExcludeSemantics(
          excluding: showLock,
          child: IgnorePointer(ignoring: showLock, child: widget.child),
        ),
        if (showLock)
          _LockScreen(
            message: _message,
            onUnlock: _unlock,
            onEmergency: _openEmergency,
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.message,
    required this.onUnlock,
    required this.onEmergency,
  });

  final String? message;
  final VoidCallback onUnlock;
  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    final saColors = context.saColors;
    return Positioned.fill(
      // Opaque, and above everything: a translucent lock would show the
      // contacts and incident titles it is meant to be covering.
      child: Material(
        color: saColors.surfaceBase,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenMarginPhone),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SaIcon(SaIconGlyph.shield, size: 48, color: saColors.ink),
                const SizedBox(height: AppSpacing.space6),
                Text(
                  'LOCKED',
                  semanticsLabel: 'Locked',
                  style: AppTypography.eyebrow.copyWith(color: saColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.space3),
                Text(
                  'Unlock SafeHer',
                  style: AppTypography.displayCondensed.copyWith(
                    color: saColors.ink,
                    fontSize: 40,
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),
                Text(
                  message ?? 'Your contacts, reports and evidence are hidden until you unlock.',
                  style: AppTypography.bodyM.copyWith(color: saColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.space8),
                SaButton(label: 'Unlock', size: SaButtonSize.lg, fullWidth: true, onPressed: onUnlock),
                const SizedBox(height: AppSpacing.space4),
                // The lock covers her data, never her alarm. A fingerprint
                // that will not read must not stand between someone and help.
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Emergency SOS, available without unlocking',
                    child: GestureDetector(
                      onTap: onEmergency,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
                        child: Text(
                          'Emergency SOS',
                          style: AppTypography.labelL.copyWith(color: AppColors.dangerOnLight),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
