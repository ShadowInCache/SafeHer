import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safeher_app/core/local/onboarding_prefs.dart';
import 'package:safeher_app/core/location/location_providers.dart';
import 'package:safeher_app/core/theme/app_theme.dart';
import 'package:safeher_app/features/contacts/data/contacts_providers.dart';
import 'package:safeher_app/features/contacts/domain/contacts_repository.dart';
import 'package:safeher_app/features/contacts/domain/models/alert_channels.dart';
import 'package:safeher_app/features/contacts/domain/models/contact.dart';
import 'package:safeher_app/features/emergency/data/emergency_providers.dart';
import 'package:safeher_app/features/emergency/domain/emergency_repository.dart';
import 'package:safeher_app/features/emergency/presentation/emergency_screen.dart';
import 'package:safeher_app/features/auth/data/auth_providers.dart';
import 'package:safeher_app/features/safety/data/safety_providers.dart';
import 'package:safeher_app/features/safety/domain/models/safety_settings.dart';

import '../../../test_utils/fake_auth_repository.dart';
import '../../../test_utils/fake_key_value_store.dart';
import '../../../test_utils/fake_location_service.dart';
import '../../../test_utils/fake_safety_repository.dart';
import 'package:safeher_app/shared/components/layout/sa_ambient_background.dart';

class _NoopEmergencyRepository implements EmergencyRepository {
  @override
  Future<DispatchOutcome> dispatchAlert({
    required String severity,
    required String summary,
    required bool auto,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async => const DispatchOutcome(contactsTotal: 0, contactsNotified: 0);
}

class _EmptyContactsRepository implements ContactsRepository {
  var verificationSends = <String>[];
  var verificationCodes = <String>[];

  /// Set to make [confirmVerificationCode] throw, as a wrong code does.
  bool verificationFails = false;

  @override
  Future<bool> sendVerificationCode(String id) async {
    verificationSends.add(id);
    return false;
  }

  @override
  Future<List<Contact>> confirmVerificationCode(String id, String code) async {
    verificationCodes.add(code);
    if (verificationFails) throw Exception('wrong code');
    return getContacts();
  }

  /// Defaults to "everything works" so existing tests are unaffected by the
  /// unreachable-contact warning; the settings tests override it.
  AlertChannels channels = const AlertChannels(sms: true, email: true, push: true);

  @override
  Future<AlertChannels> getAlertChannels() async => channels;

  @override
  Future<List<Contact>> updateContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    String? email,
  }) async => getContacts();

  @override
  Future<List<Contact>> getContacts() async => const [];

  @override
  Future<List<Contact>> addContact(
    String name,
    String phone,
    String relationship, {
    String? email,
  }) async => const [];

  @override
  Future<List<Contact>> removeContact(String id) async => const [];

  @override
  Future<List<Contact>> reorderContacts(List<Contact> newOrder) async => newOrder;
}

Widget _harness({required FakeSafetyRepository safety}) {
  return ProviderScope(
    overrides: [
      safetyRepositoryProvider.overrideWithValue(safety),
      emergencyRepositoryProvider.overrideWithValue(_NoopEmergencyRepository()),
      contactsRepositoryProvider.overrideWithValue(_EmptyContactsRepository()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      localKeyValueStoreProvider.overrideWithValue(FakeKeyValueStore()),
      // Safety preferences only load for a signed-in user, so the gate under
      // test needs a session to exist at all.
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    ],
    child: MaterialApp.router(
    // Mirrors main.dart's shell so screens render over the same ambient
    // field users see; the scaffold background is transparent by design.
    builder: (context, child) =>
        SaAmbientBackground(child: child ?? const SizedBox.shrink()),
      theme: AppTheme.dark,
      routerConfig: GoRouter(
        initialLocation: '/emergency?auto=1',
        routes: [
          GoRoute(
            path: '/emergency',
            builder: (_, state) =>
                EmergencyScreen(autoStart: state.uri.queryParameters['auto'] == '1'),
          ),
          GoRoute(path: '/home', builder: (_, __) => const Scaffold(body: Text('home-stub'))),
        ],
      ),
    ),
  );
}

FakeSafetyRepository _repo({
  required bool requirePin,
  PinVerificationResult verifyResult = const PinVerificationResult(valid: true),
}) {
  return FakeSafetyRepository(
    preferences: const SafetyPreferences.defaults().copyWith(requirePinToCancel: true).copyWith(
      requirePinToCancel: requirePin,
    ),
    pinStatus: SafetyPinStatus(isSet: requirePin),
    verifyResult: verifyResult,
  );
}

void main() {
  group('SOS cancel PIN gate', () {
    testWidgets('auto-start opens the countdown rather than dispatching immediately', (tester) async {
      await tester.pumpWidget(_harness(safety: _repo(requirePin: false)));
      await tester.pump(const Duration(milliseconds: 200));

      // The countdown is the confirmation step for shake/voice triggers too.
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancels straight away when no PIN is required', (tester) async {
      final safety = _repo(requirePin: false);
      await tester.pumpWidget(_harness(safety: safety));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Cancel'));
      // Discrete pumps rather than pumpAndSettle: the pre-activation stage
      // this returns to has a looping pulse animation that never settles.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(safety.verifiedPins, isEmpty, reason: 'no PIN should be requested');
      expect(find.text('Cancel'), findsNothing, reason: 'countdown should have stopped');
    });

    testWidgets('demands the PIN before cancelling when the user requires it', (tester) async {
      final safety = _repo(requirePin: true);
      await tester.pumpWidget(_harness(safety: safety));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Enter Safety PIN'), findsOneWidget);
      expect(
        find.textContaining('countdown keeps running'),
        findsOneWidget,
        reason: 'the user must be told the alert is still live',
      );
    });

    testWidgets('a wrong PIN does not cancel the alert', (tester) async {
      final safety = _repo(
        requirePin: true,
        verifyResult: const PinVerificationResult(valid: false, attemptsRemaining: 3),
      );
      await tester.pumpWidget(_harness(safety: safety));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '0000');
      await tester.tap(find.text('Cancel the alert'));
      await tester.pumpAndSettle();

      expect(safety.verifiedPins, ['0000']);
      expect(find.textContaining('Incorrect PIN'), findsOneWidget);
      // The sheet stays up: the alert has not been stood down.
      expect(find.text('Enter Safety PIN'), findsOneWidget);
    });

    testWidgets('"Keep alert running" leaves the countdown alive', (tester) async {
      final safety = _repo(requirePin: true);
      await tester.pumpWidget(_harness(safety: safety));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep alert running'));
      await tester.pumpAndSettle();

      expect(safety.verifiedPins, isEmpty);
      expect(find.text('Cancel'), findsOneWidget, reason: 'countdown still running');
    });
  });
}
