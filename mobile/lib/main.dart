import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared/components/layout/sa_ambient_background.dart';
import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/local/app_preferences.dart';
import 'core/offline/offline_queue_providers.dart';
import 'core/router/app_router.dart';
import 'core/security/app_lock.dart';
import 'core/theme/app_theme.dart';
import 'features/devices/data/glove_autoconnect_providers.dart';
import 'features/devices/data/glove_link_providers.dart';
import 'features/safety/presentation/widgets/safety_trigger_listener.dart';
import 'firebase_options.dart';

void _bleLog(String message) {
  if (kDebugMode) debugPrint('[BLE] $message');
}

/// How long startup may take before it is treated as hung.
///
/// A throw is not the only way `main` can fail to reach `runApp`. A box that
/// never opens, or a platform channel that never answers, leaves an `await`
/// pending forever — and an `await` that never completes cannot be caught.
/// The screen stays black with nothing in the log, which is precisely the
/// failure this file shipped with.
const _startupBudget = Duration(seconds: 15);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **`runApp` is now reached on every path.**
  //
  // This used to be two bare `await`s with `runApp` after them. Anything that
  // threw — a Firebase misconfiguration, a Hive box that would not open — meant
  // `runApp` was never called, so Android showed a black screen with nothing on
  // it and nothing in the log to say why. On a safety app that is the worst
  // possible failure: indistinguishable from a dead phone, and undebuggable
  // without a cable.
  //
  // Firebase and local storage fail differently and are treated differently.
  // Firebase being down costs sign-in and push; the app still has SOS, the
  // shake gesture and contacts, so it starts and says what is degraded. Local
  // storage is not survivable — `prefsBox` is read through `getIt` all over the
  // app and would throw on first access — so that one stops here, visibly.
  if (!AppConfig.useMockApi) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(_startupBudget);
    } catch (error, stackTrace) {
      // Reported, not fatal. Sign-in and push will not work; everything that
      // does not need the network still will.
      debugPrint('SafeHer: Firebase did not start: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
    }
  }

  try {
    await configureDependencies().timeout(_startupBudget);
  } catch (error, stackTrace) {
    debugPrint('SafeHer: local storage did not start: $error');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
    runApp(_StartupFailureApp(detail: '$error'));
    return;
  }

  runApp(const ProviderScope(child: _AppLifecycleLogger(child: SafeHerApp())));
}

/// Shown when the app genuinely cannot start.
///
/// Deliberately built from nothing but `MaterialApp` and `Text`: it has to
/// render when dependency injection, preferences and the theme are all
/// unavailable, so it may not touch any of them. Its whole job is to replace a
/// black screen with a sentence.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SafeHer could not start',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Its local storage would not open, so the app cannot run. '
                  'Reopening may fix it. If it does not, reinstalling will — '
                  'but that clears anything saved on this device.',
                  style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 20),
                Text(
                  detail,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logs app-lifecycle transitions under `[BLE]` — not because the app
/// lifecycle is BLE's concern, but because "close and reopen the app" was
/// the one reliable fix for the connected-but-no-data bug this logging was
/// added to chase down: `main.dart`'s providers rebuilding fresh on a real
/// process restart is what actually recovered it, so seeing *whether* a
/// resume is a fresh process versus a backgrounded one still running is
/// part of that evidence.
class _AppLifecycleLogger extends StatefulWidget {
  const _AppLifecycleLogger({required this.child});

  final Widget child;

  @override
  State<_AppLifecycleLogger> createState() => _AppLifecycleLoggerState();
}

class _AppLifecycleLoggerState extends State<_AppLifecycleLogger> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bleLog('app launched');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bleLog('app terminated/cleanup');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _bleLog('app resumed');
      case AppLifecycleState.paused:
        _bleLog('app paused');
      case AppLifecycleState.detached:
        _bleLog('app detached');
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SafeHerApp extends ConsumerWidget {
  const SafeHerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Keeps the queue drainer alive for the app's whole lifetime; it has
    // no UI, it just listens for connectivity to come back.
    ref.watch(offlineQueueDrainerProvider);
    // Keeps the glove auto-connect attempt alive for the app's whole
    // lifetime too, for the same reason: it has no UI, and nothing else
    // in the widget tree is guaranteed to be watching it on every launch.
    // Without this, a closed-and-reopened app (or a launch before the
    // glove had power) never resumes streaming until the user manually
    // re-opens the pairing sheet — see that provider's doc comment.
    ref.watch(gloveAutoConnectProvider);
    // GloveLink owns the one classification/telemetry subscription and
    // must be watched from here, not left to whichever screen happens to
    // be on top: it only reacts to BlePairingController's stage changes
    // *after* something has attached its listener (a `ref.listen`
    // attached after a state change already happened never sees that
    // change). Before this, it was only watched incidentally from the
    // Home screen — real, but not guaranteed if a connection completed
    // before Home ever built. Explicit here removes that race.
    ref.watch(gloveLinkProvider);
    // Reconnect-after-a-drop (e.g. the ESP32 lost power and came back) is
    // BlePairingController's own job — see that class's doc comment for why
    // a separate GloveConnectionManager provider used to also do this, and
    // why that was actively harmful rather than merely redundant. No
    // separate watch is needed here for it: gloveLinkProvider above already
    // keeps BlePairingController alive for the whole session via its
    // ref.listen.
    // Profile > Preferences > Dark Mode is a plain on/off switch (not a
    // 3-way system/light/dark picker), so once the user has touched it we
    // honor that explicit choice over the platform setting.
    final darkModeEnabled = ref.watch(appPreferencesProvider).darkModeEnabled;
    return MaterialApp.router(
      title: 'SafeHer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: darkModeEnabled ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
      // Hosts the opt-in shake trigger above the router so the gesture works
      // from any screen. It listens only while the user has it switched on.
      // The aurora sits below the router so every screen inherits it, and
      // inside the theme scope so it can read the active brightness.
      // AppLock sits inside the ambient ground and outside the trigger
      // listener: the lock covers what is on screen, while the shake gesture
      // and the rest of the app keep running underneath it. Locking is opt-in
      // (Profile > Security) and the lock screen keeps its own route to SOS.
      builder: (context, child) => SaAmbientBackground(
        child: AppLock(
          child: SafetyTriggerListener(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
