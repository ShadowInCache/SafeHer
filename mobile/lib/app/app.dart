import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'bootstrap.dart';
import 'core/constants/app_routes.dart';
import 'core/localization/app_localizations.dart';
import 'core/theme/premium_theme.dart';
import 'shared/state/providers.dart';

class SafeHerBootstrap extends ConsumerStatefulWidget {
  const SafeHerBootstrap({super.key});

  @override
  ConsumerState<SafeHerBootstrap> createState() => _SafeHerBootstrapState();
}

class _SafeHerBootstrapState extends ConsumerState<SafeHerBootstrap> {
  late final Future<BootstrapBundle> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    final environment = ref.read(environmentProvider);
    _bootstrapFuture = BootstrapBundle.initialize(environment);
  }

  MaterialApp _buildBootstrapShell(Widget child) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: PremiumTheme.darkTheme(),
      // Allow any browser initial route while bootstrap is still loading.
      onGenerateRoute: (_) =>
          MaterialPageRoute<void>(builder: (context) => Scaffold(body: child)),
      home: Scaffold(body: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BootstrapBundle>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildBootstrapShell(
            Container(
              decoration: const BoxDecoration(
                gradient: PremiumTheme.heroGradient,
              ),
              child: const Center(child: CircularProgressIndicator.adaptive()),
            ),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildBootstrapShell(
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 56),
                    const SizedBox(height: 16),
                    const Text('SafeHer failed to initialize'),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ProviderScope(
          overrides: [
            bootstrapBundleProvider.overrideWithValue(snapshot.data!),
          ],
          child: const SafeHerApp(),
        );
      },
    );
  }
}

class SafeHerApp extends ConsumerWidget {
  const SafeHerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SafeHer',
      debugShowCheckedModeBanner: false,
      theme: PremiumTheme.lightTheme(),
      darkTheme: PremiumTheme.darkTheme(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
