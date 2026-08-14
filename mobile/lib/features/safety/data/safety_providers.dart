import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_providers.dart';
import '../../../core/location/location_result.dart';
import '../../../core/network/network_providers.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/models/safe_journey.dart';
import '../domain/models/safety_settings.dart';
import '../domain/safety_repository.dart';
import 'journey_repository_remote.dart';
import 'safety_repository_mock.dart';
import 'safety_repository_remote.dart';

part 'safety_providers.g.dart';

@riverpod
SafetyRepository safetyRepository(Ref ref) {
  if (AppConfig.useMockApi) return SafetyRepositoryMock();
  return SafetyRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

@riverpod
JourneyRepository journeyRepository(Ref ref) {
  if (AppConfig.useMockApi) return JourneyRepositoryMock();
  return JourneyRepositoryRemote(apiClient: ref.watch(apiClientProvider));
}

/// The user's opt-in trigger settings. Kept alive because the shake listener
/// and the SOS cancel flow both depend on it outside any one screen.
@Riverpod(keepAlive: true)
class SafetyPreferencesNotifier extends _$SafetyPreferencesNotifier {
  @override
  Future<SafetyPreferences> build() async {
    // `SafetyTriggerListener` mounts above the router, so this provider is
    // alive from app launch — before sign-in. Calling an authenticated
    // endpoint there fires a guaranteed-to-fail request on the splash screen
    // (and a visible connection error when the backend isn't up yet).
    //
    // Defaults are all-off, so the shake trigger stays dormant until a real
    // signed-in preference says otherwise. `refreshAfterSignIn` reloads this
    // once a session exists.
    final hasSession = await ref.watch(authRepositoryProvider).hasActiveSession();
    if (!hasSession) return const SafetyPreferences.defaults();

    return ref.watch(safetyRepositoryProvider).getPreferences();
  }

  /// Call after a successful sign-in (or sign-out) so the all-off defaults
  /// used while unauthenticated are replaced by the account's real settings.
  void refreshAfterSignIn() => ref.invalidateSelf();

  /// Named `save` rather than `update` because `AsyncNotifier` already
  /// defines an `update` with a different signature.
  Future<void> save(SafetyPreferences preferences) async {
    final previous = state.valueOrNull;
    state = AsyncData(preferences);
    try {
      state = AsyncData(await ref.read(safetyRepositoryProvider).updatePreferences(preferences));
    } catch (error, stack) {
      // Roll back rather than leave the UI showing a switch the server rejected
      // (e.g. requiring a PIN to cancel before one has been created).
      if (previous != null) state = AsyncData(previous);
      state = AsyncError(error, stack);
      rethrow;
    }
  }
}

@riverpod
class SafetyPinStatusNotifier extends _$SafetyPinStatusNotifier {
  @override
  Future<SafetyPinStatus> build() => ref.watch(safetyRepositoryProvider).getPinStatus();

  Future<void> setPin({required String pin, String? currentPin}) async {
    await ref.read(safetyRepositoryProvider).setPin(pin: pin, currentPin: currentPin);
    ref.invalidateSelf();
  }

  Future<void> removePin(String pin) async {
    await ref.read(safetyRepositoryProvider).removePin(pin);
    ref.invalidateSelf();
    ref.invalidate(safetyPreferencesNotifierProvider);
  }
}

/// The active journey plus the periodic real-GPS breadcrumb loop.
///
/// The loop only runs while a journey is genuinely active and the user has
/// left `journeyAutoShareLocation` on. Every point posted is a real fix from
/// [LocationService] — a failed fix posts nothing rather than repeating the
/// last known position as if it were fresh.
@Riverpod(keepAlive: true)
class ActiveJourneyNotifier extends _$ActiveJourneyNotifier {
  Timer? _shareTimer;

  @override
  Future<SafeJourney?> build() async {
    ref.onDispose(() => _shareTimer?.cancel());
    // Re-evaluate whenever the preference resolves or changes: sharing must
    // not begin while we still don't know whether the user allowed it.
    ref.listen(safetyPreferencesNotifierProvider, (_, __) => _syncSharing(state.valueOrNull));
    final journey = await ref.watch(journeyRepositoryProvider).getActiveJourney();
    _syncSharing(journey);
    return journey;
  }

  static const _shareInterval = Duration(minutes: 2);

  void _syncSharing(SafeJourney? journey) {
    _shareTimer?.cancel();
    _shareTimer = null;
    if (journey == null || !journey.isInProgress) return;

    // Absent (still loading) counts as "not yet permitted", not as consent.
    final prefs = ref.read(safetyPreferencesNotifierProvider).valueOrNull;
    if (prefs == null || !prefs.journeyAutoShareLocation) return;

    _shareTimer = Timer.periodic(_shareInterval, (_) => _shareLocation());
    unawaited(_shareLocation());
  }

  Future<void> _shareLocation() async {
    final journey = state.valueOrNull;
    if (journey == null || !journey.isInProgress) return;

    final fix = await ref.read(locationServiceProvider).getCurrentLocation();
    if (fix is! LocationAvailable) return; // No real fix -> nothing to report.

    try {
      await ref.read(journeyRepositoryProvider).pushLocation(
        journeyId: journey.id,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMetres: fix.accuracyMeters,
      );
    } catch (_) {
      // A dropped breadcrumb is not worth surfacing; the next tick retries.
    }
  }

  Future<SafeJourney> start({
    required String destinationLabel,
    required int expectedDurationMinutes,
    double? destinationLat,
    double? destinationLng,
    int? checkInIntervalMinutes,
    List<String> contactIds = const [],
  }) async {
    final journey = await ref.read(journeyRepositoryProvider).startJourney(
      destinationLabel: destinationLabel,
      expectedDurationMinutes: expectedDurationMinutes,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      checkInIntervalMinutes: checkInIntervalMinutes,
      contactIds: contactIds,
    );
    state = AsyncData(journey);
    _syncSharing(journey);
    return journey;
  }

  Future<void> checkIn() async {
    final journey = state.valueOrNull;
    if (journey == null) return;
    state = AsyncData(await ref.read(journeyRepositoryProvider).checkIn(journey.id));
  }

  Future<void> markArrived() => _finish((repo, id) => repo.markArrived(id));

  Future<void> cancel() => _finish((repo, id) => repo.cancel(id));

  /// Runs the overdue policy. The server re-checks the deadline, so calling
  /// this early is rejected there rather than trusted here.
  Future<void> escalate() async {
    final journey = state.valueOrNull;
    if (journey == null) return;
    try {
      state = AsyncData(await ref.read(journeyRepositoryProvider).escalate(journey.id));
    } catch (_) {
      // Already escalated, or not actually out of time yet.
    }
  }

  Future<void> _finish(Future<SafeJourney> Function(JourneyRepository, String) action) async {
    final journey = state.valueOrNull;
    if (journey == null) return;
    await action(ref.read(journeyRepositoryProvider), journey.id);
    _shareTimer?.cancel();
    _shareTimer = null;
    state = const AsyncData(null);
    ref.invalidate(journeyHistoryProvider);
  }
}

@riverpod
Future<List<SafeJourney>> journeyHistory(Ref ref) =>
    ref.watch(journeyRepositoryProvider).listJourneys();
