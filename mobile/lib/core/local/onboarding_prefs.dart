import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../di/injection.dart';
import 'local_key_value_store.dart';

part 'onboarding_prefs.g.dart';

/// Tiny flag deciding whether Splash routes to Onboarding or straight past
/// it. Kept separate from the Phase 5 offline queue, which is a different
/// (request-retry) concern.
class OnboardingPrefs {
  const OnboardingPrefs(this._store);

  final LocalKeyValueStore _store;
  static const _key = 'hasSeenOnboarding';

  bool get hasSeenOnboarding => _store.getBool(_key);

  Future<void> setSeenOnboarding() => _store.setBool(_key, true);
}

@riverpod
LocalKeyValueStore localKeyValueStore(Ref ref) => HiveKeyValueStore(prefsBox);

@riverpod
OnboardingPrefs onboardingPrefs(Ref ref) => OnboardingPrefs(ref.watch(localKeyValueStoreProvider));
