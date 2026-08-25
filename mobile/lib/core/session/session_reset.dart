import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/app_preferences.dart';
import '../../features/contacts/data/contacts_providers.dart';
import '../../features/devices/data/device_providers.dart';
import '../../features/emergency/data/emergency_providers.dart';
import '../../features/monitoring/data/monitoring_providers.dart';
import '../../features/profile/data/profile_providers.dart';
import '../../features/reports/data/reports_providers.dart';
import '../../features/safety/data/safety_providers.dart';

/// Forgets everything the signed-out account left in memory.
///
/// **The bug this fixes.** Several providers are declared
/// `@Riverpod(keepAlive: true)` so their state survives navigation — which
/// is right for a live BLE link or an in-flight dispatch, and wrong for
/// anything belonging to a person. Nothing invalidated them on sign-out, so
/// the cached list simply stayed. Sign out, sign in as someone else, and the
/// previous account's emergency contacts were on screen: their names, their
/// phone numbers, their email addresses.
///
/// Found on a real device by signing into a second account. The server was
/// never wrong — its rows were correctly scoped the whole time — which is
/// what made it invisible from the backend and from every test that drove
/// one user.
///
/// Called on sign-out *and* on sign-in. Sign-out alone would be enough if
/// every path went through it, but a token that expires, an app killed
/// mid-session, or a `deleteAccount` all end a session without passing
/// through the button — and the cost of an extra refetch is a spinner, while
/// the cost of a miss is showing one woman another woman's emergency
/// contacts.
void resetSessionScopedState(WidgetRef ref) {
  _reset(ref.invalidate);
  _clearAccountScopedPreferences(ref.read(appPreferencesProvider), ref.invalidate);
}

/// Same, for callers holding a [Ref] rather than a [WidgetRef].
void resetSessionScopedStateFromRef(Ref ref) {
  _reset(ref.invalidate);
  _clearAccountScopedPreferences(ref.read(appPreferencesProvider), ref.invalidate);
}

/// Preferences are persisted, so invalidating the provider is not enough --
/// it would just re-read the previous account's values straight back out of
/// Hive. They have to be written back to their defaults.
void _clearAccountScopedPreferences(
  AppPreferences preferences,
  void Function(ProviderOrFamily) invalidate,
) {
  // Fire and forget: the write is local and the provider is invalidated
  // immediately so the UI stops showing the old values either way.
  preferences.clearAccountScoped();
  invalidate(appPreferencesProvider);
}

void _reset(void Function(ProviderOrFamily) invalidate) {
  // Everything here is scoped to one person. Deliberately not a catch-all
  // container reset: the offline queue and the BLE link are also long-lived
  // but tearing them down is not obviously right (see below), and a
  // scattergun that disconnects a paired glove on sign-out would be a new
  // bug wearing a fix's clothes.
  invalidate(contactsNotifierProvider);
  invalidate(userProfileProvider);
  invalidate(devicesProvider);
  invalidate(emergencyDispatchNotifierProvider);
  invalidate(liveMonitoringControllerProvider);
  invalidate(safetyPreferencesNotifierProvider);
  invalidate(activeJourneyNotifierProvider);
  invalidate(reportsListProvider);
}

// Not reset here, and why:
//
// * **The offline queue.** It can hold an undelivered emergency alert. That
//   alert belongs to the account that raised it, so replaying it under a new
//   session would attribute one person's emergency to another — but dropping
//   it loses an alert someone is waiting on. Neither is acceptable as a
//   silent default, so the queue is left alone and the question is recorded
//   in `docs/TRACEABILITY.md` rather than answered by accident here.
//
// * **The BLE connection.** Bound to hardware rather than to an account, and
//   disconnecting a worn glove because someone switched profiles would take
//   away protection to fix a display bug.
