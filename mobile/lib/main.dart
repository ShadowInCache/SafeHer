import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only touch Firebase once a real flavor is selected — AppConfig.useMockApi
  // defaults to true, so a fresh checkout never needs Firebase configured to
  // run.
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
    return MaterialApp.router(
      title: 'SafeHer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
