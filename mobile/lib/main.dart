import 'package:firebase_core/firebase_core.dart';
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
import 'features/safety/presentation/widgets/safety_trigger_listener.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skipped under the fixture-data flavor (`--dart-define=USE_MOCK_API=true`),
  // so UI-only work never needs Firebase configured. The default is the real
  // flavor, which does initialise it.
  if (!AppConfig.useMockApi) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await configureDependencies();
  runApp(const ProviderScope(child: SafeHerApp()));
}

class SafeHerApp extends ConsumerWidget {
  const SafeHerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // Keeps the queue drainer alive for the app's whole lifetime; it has
    // no UI, it just listens for connectivity to come back.
    ref.watch(offlineQueueDrainerProvider);
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
