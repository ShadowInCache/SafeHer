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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skipped under the fixture-data flavor (`--dart-define=USE_MOCK_API=true`),
  // so UI-only work never needs Firebase configured. The default is the real
  // flavor, which does initialise it.
  if (!AppConfig.useMockApi) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await configureDependencies();
  runApp(const ProviderScope(child: _AppLifecycleLogger(child: SafeHerApp())));
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
