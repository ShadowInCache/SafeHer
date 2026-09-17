import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

/// Why the process is being kept alive.
///
/// The service is one operating-system object with one lifetime, and SafeHer
/// has two independent things that need it. Keeping them as separate reasons
/// rather than one boolean is what stops the second from switching off the
/// first: a journey ending while the glove is still connected must not take
/// the glove's BLE stream down with it.
///
/// The set of live reasons also decides the Android *service type*, which on
/// Android 14+ is enforced against the permissions actually held rather than
/// being descriptive. Declaring a type for work that is not happening is how a
/// service gets refused at start; declaring none for work that is happening is
/// how the platform mutes it mid-journey.
enum WatchReason {
  /// A glove is connected and its classifications are being voted on.
  ///
  /// Needs `connectedDevice`: this is a BLE link to a wearable.
  glove,

  /// A Safe Journey is armed, so the microphone is listening continuously.
  ///
  /// Needs `microphone`, without which Android 14+ stops delivering audio to a
  /// backgrounded process — which is the entire case the service exists for.
  journey,
}

/// Keeps the app's process alive so a connected glove can still raise the
/// alarm with the phone in a pocket.
///
/// **The gap this closes.** The glove runs its model on the ESP32 and notifies
/// classifications over BLE, and the app votes on them and opens the SOS
/// countdown. All of that worked only while SafeHer was on screen. Android
/// freezes a backgrounded process: the BLE callbacks stop being delivered, and
/// the exact situation the feature exists for — a phone pocketed, a hand
/// grabbed — raised nothing at all.
///
/// A foreground service is the only supported way to tell Android that this
/// process is doing something the user asked for and must not be frozen. The
/// persistent notification it requires is not a cost to be minimised here: it
/// is the honest signal that SafeHer is watching, and the user's way to see
/// that it stopped.
///
/// ## Why this is an interface
///
/// The concrete implementation talks to a plugin that needs a real Android
/// activity, so nothing behind it can run in a widget test. Everything that
/// decides *whether* to watch is therefore written against this seam and
/// tested against [NoopForegroundService], the same way [BleService] is.
abstract class SafetyForegroundService {
  /// Whether the service is running right now.
  ///
  /// Asked of the platform rather than remembered in a field: the system can
  /// stop a service without telling us, and a cached `true` would let the app
  /// claim it is watching when it is not — the failure this codebase keeps
  /// having to fix.
  Future<bool> isRunning();

  /// Starts watching, for the given [reasons].
  ///
  /// Returns whether the service is actually running afterwards, so callers
  /// report what happened rather than what they asked for.
  ///
  /// [reasons] must not be empty: a service with nothing to keep alive is the
  /// "watching" notification over nothing that this file exists to avoid.
  /// Calling it again with a different set re-declares the service types, which
  /// is how a journey starting under an already-running glove watch gets
  /// microphone access added.
  Future<bool> start({required Set<WatchReason> reasons});

  /// Stops watching.
  Future<void> stop();

  /// Wakes the screen and brings the app forward.
  ///
  /// Called when the alarm fires with the app in the background. The countdown
  /// is a chance to say "I'm fine", and a countdown running behind a dark
  /// screen is not one.
  Future<void> bringToForeground();
}

/// The real service, on Android.
class PluginForegroundService implements SafetyForegroundService {
  PluginForegroundService();

  static const _channelId = 'safeher_glove_watch';

  bool _initialised = false;

  void _ensureInitialised() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Safety monitoring',
        channelDescription:
            'Shown while SafeHer is watching for a fall or for distress.',
        // LOW, and no sound or vibration: this notification exists to be
        // available, not to interrupt. The alarm interrupts.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // No repeating task and no callback: the work happens on the main
        // isolate, where the BLE subscription and the vote already live.
        // Starting a second isolate would mean a second BLE client and two
        // detectors disagreeing about whether to summon help.
        eventAction: ForegroundTaskEventAction.nothing(),
        // The CPU has to stay awake or the BLE callbacks this exists to
        // receive are simply not delivered on a sleeping device.
        allowWakeLock: true,
        // Deliberately not restarted on boot. Watching is a thing the user
        // switched on for a glove that is currently connected; silently
        // resuming it after a reboot, with no glove in range, would show a
        // "watching" notification over nothing.
        autoRunOnBoot: false,
        allowAutoRestart: true,
      ),
    );
    _initialised = true;
  }

  /// Runs a platform call, treating any failure as "the service is not
  /// running".
  ///
  /// The channel is not always there to answer: the plugin is unregistered
  /// under `flutter test` and in any host that has not registered it, and it
  /// throws rather than returning. Every failure here means the same thing —
  /// nothing is keeping this process alive — and the app has to be able to
  /// say so. Letting a `MissingPluginException` escape would instead take
  /// down the screen that was trying to report it.
  Future<T> _guard<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on Object catch (error) {
      debugPrint('SafeHer: foreground service call failed: $error');
      return fallback;
    }
  }

  @override
  Future<bool> isRunning() =>
      _guard(() => FlutterForegroundTask.isRunningService, false);

  /// The Android service types the live [reasons] actually justify.
  ///
  /// `location` is unconditional, matching what this service has always
  /// declared: an alarm raised from here attaches the user's position whichever
  /// reason woke it. `connectedDevice` and `microphone` are added only for work
  /// that is genuinely running.
  ///
  /// **The microphone type is gated on the permission being held.** Android 14
  /// checks the declared types against granted permissions and refuses to start
  /// the service when one is missing — so declaring `microphone` after the user
  /// denied it would not gain background audio, it would lose the service
  /// altogether, and with it the glove's BLE stream. A denied microphone has to
  /// cost only the microphone.
  Future<List<ForegroundServiceTypes>> _serviceTypesFor(
    Set<WatchReason> reasons,
  ) async {
    final types = <ForegroundServiceTypes>[ForegroundServiceTypes.location];
    if (reasons.contains(WatchReason.glove)) {
      types.add(ForegroundServiceTypes.connectedDevice);
    }
    if (reasons.contains(WatchReason.journey) && await _microphoneGranted()) {
      types.add(ForegroundServiceTypes.microphone);
    }
    return types;
  }

  Future<bool> _microphoneGranted() async {
    // `permission_handler` has no web implementation and throws in hosts that
    // have not registered it. Unknown is treated as not granted: the cost is a
    // service without the microphone type, which is recoverable. The cost of
    // guessing the other way is no service at all.
    final status = await _guard(
      () => Permission.microphone.status,
      PermissionStatus.denied,
    );
    return status.isGranted;
  }

  /// What the notification says, which is the user's only window onto what
  /// this process is doing. It names the reasons rather than describing the
  /// service, because "SafeHer is watching your glove" over an armed journey
  /// with no glove connected would be false.
  static ({String title, String text}) _notificationFor(
    Set<WatchReason> reasons,
  ) {
    final glove = reasons.contains(WatchReason.glove);
    final journey = reasons.contains(WatchReason.journey);
    if (glove && journey) {
      return (
        title: 'SafeHer is watching',
        text: 'Your glove and journey detection keep working while your '
            'phone is away.',
      );
    }
    if (journey) {
      return (
        title: 'SafeHer is watching your journey',
        text: 'Listening for distress while your phone is away.',
      );
    }
    return (
      title: 'SafeHer is watching your glove',
      text: 'Detection keeps working while your phone is away.',
    );
  }

  @override
  Future<bool> start({required Set<WatchReason> reasons}) async {
    assert(reasons.isNotEmpty, 'a service with no reason is a notification over nothing');
    if (reasons.isEmpty) return false;
    // Deliberately not short-circuiting on an already-running service: the
    // reasons may have grown since it started, and the new ones need their
    // service types declared. `startService` on a running service updates it.
    _ensureInitialised();

    // Android 13+ drops the notification silently without this, and a
    // foreground service whose notification cannot be posted is stopped by
    // the system. Asking is therefore part of starting, not a nicety.
    final permission = await _guard(
      FlutterForegroundTask.checkNotificationPermission,
      NotificationPermission.denied,
    );
    if (permission != NotificationPermission.granted) {
      final granted = await _guard(
        FlutterForegroundTask.requestNotificationPermission,
        NotificationPermission.denied,
      );
      if (granted != NotificationPermission.granted) return false;
    }

    final types = await _serviceTypesFor(reasons);
    final notification = _notificationFor(reasons);

    final result = await _guard(
      () => FlutterForegroundTask.startService(
        serviceTypes: types,
        notificationTitle: notification.title,
        notificationText: notification.text,
      ),
      const ServiceRequestFailure(error: 'platform channel unavailable'),
    );
    if (result is ServiceRequestFailure) {
      // Reported, not thrown. A phone that refuses the service still has SOS,
      // the shake gesture and contacts, and the caller's job is to say so
      // rather than to crash on the way to saying it.
      debugPrint('SafeHer: foreground service failed to start: ${result.error}');
      return false;
    }
    // Asked again rather than trusting the success result: this is the value
    // the UI turns into "you can put your phone in your pocket".
    return isRunning();
  }

  @override
  Future<void> stop() async {
    if (!await isRunning()) return;
    await _guard(FlutterForegroundTask.stopService, const ServiceRequestSuccess());
  }

  @override
  Future<void> bringToForeground() async {
    await _guard(() async {
      FlutterForegroundTask.wakeUpScreen();
      FlutterForegroundTask.launchApp();
    }, null);
  }
}

/// Does nothing, and says so.
///
/// Used on platforms with no such concept (iOS keeps a BLE app alive through
/// background modes instead, which is a separate piece of work) and in tests.
/// [isRunning] returns false so callers describing the app's state describe
/// the truth on those platforms rather than inheriting Android's.
class NoopForegroundService implements SafetyForegroundService {
  const NoopForegroundService();

  @override
  Future<bool> isRunning() async => false;

  @override
  Future<bool> start({required Set<WatchReason> reasons}) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> bringToForeground() async {}
}

/// The service for the platform actually being run on.
///
/// `defaultTargetPlatform` rather than `dart:io`'s `Platform`: importing
/// `dart:io` anywhere web-reachable throws in a browser, and a guard test
/// enforces that. The `kIsWeb` term is not redundant either — a browser on an
/// Android phone reports `TargetPlatform.android`, and there is no foreground
/// service there.
SafetyForegroundService createForegroundService() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return PluginForegroundService();
  }
  return const NoopForegroundService();
}
