import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'app/core/config/app_environment.dart';
import 'app/shared/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final environment = AppEnvironment.fromDefines();

  runApp(
    ProviderScope(
      overrides: [environmentProvider.overrideWithValue(environment)],
      child: const SafeHerBootstrap(),
    ),
  );
}
