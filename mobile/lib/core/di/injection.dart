import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

final getIt = GetIt.instance;

const prefsBoxName = 'safeher_prefs';

/// Registers cross-cutting singletons (local storage, HTTP client, etc.)
/// that Riverpod providers wrap rather than depending on directly. Call
/// once from main() before runApp.
Future<void> configureDependencies() async {
  await Hive.initFlutter();
  final prefsBox = await Hive.openBox(prefsBoxName);
  getIt.registerSingleton<Box>(prefsBox, instanceName: prefsBoxName);
}

Box get prefsBox => getIt<Box>(instanceName: prefsBoxName);
