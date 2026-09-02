import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'local_key_value_store.dart';
import 'onboarding_prefs.dart';

part 'app_preferences.g.dart';

const _kThreatThreshold = 'threatThreshold';
const _kCountdownSeconds = 'countdownSeconds';

/// How long the SOS countdown runs before the alert goes out, unless the user
/// has chosen otherwise in Profile > Preferences > Countdown Duration.
///
/// A deliberate deviation from the SRS: FR-EMG-03 specifies 10 seconds, and
/// this ships 5 on the product owner's call. The trade is real in both
/// directions -- five seconds gets help moving sooner when the alert is
/// genuine, and halves the time available to call off a false one -- so it is
/// recorded rather than quietly changed.
///
/// It lives here, as one constant, because the value was previously written
/// out twice: here and as the emergency screen's pre-preference fallback. Two
/// copies of a number that decides how long someone has to stop an alert is
/// one copy too many.
const kDefaultCountdownSeconds = 5;
const _kAutoRecord = 'autoRecordEnabled';
const _kDarkMode = 'darkModeEnabled';
const _kBiometric = 'biometricEnabled';
const _kGlassesHost = 'glassesHost';

/// User-configurable safety/appearance preferences (Profile > Preferences),
/// persisted via [LocalKeyValueStore] so they survive app restarts.
class AppPreferences {
  AppPreferences(this._store);

  final LocalKeyValueStore _store;

  /// 0.50–0.95, the AI auto-SOS trigger sensitivity. Default matches
  /// FR-EMG-02's spec default of 0.75.
  double get threatThreshold => _store.getDouble(_kThreatThreshold, defaultValue: 0.75);

  Future<void> setThreatThreshold(double value) => _store.setDouble(_kThreatThreshold, value);

  /// 5, 10, or 15 — the Emergency screen's cancellable countdown length.
  /// SOS countdown length, in seconds. See [kDefaultCountdownSeconds].
  int get countdownSeconds => _store.getInt(_kCountdownSeconds, defaultValue: kDefaultCountdownSeconds);

  Future<void> setCountdownSeconds(int value) => _store.setInt(_kCountdownSeconds, value);

  bool get autoRecordEnabled => _store.getBool(_kAutoRecord, defaultValue: true);

  Future<void> setAutoRecordEnabled(bool value) => _store.setBool(_kAutoRecord, value);

  /// Defaults to whatever the platform's brightness is at first read, so
  /// installing the app doesn't override the user's system preference
  /// until they explicitly touch this switch.
  bool get darkModeEnabled =>
      _store.getBool(_kDarkMode, defaultValue: SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);

  Future<void> setDarkModeEnabled(bool value) => _store.setBool(_kDarkMode, value);

  bool get biometricEnabled => _store.getBool(_kBiometric, defaultValue: false);

  /// Where the glasses serve their video, as `host` or `host:port`.
  ///
  /// Empty until a pair of glasses has actually been paired, and that emptiness
  /// is load-bearing: with no address there is no stream, so weapon detection
  /// reports nothing rather than reporting calm. A default guess like
  /// `192.168.4.1` would be worse than nothing — it would let the app claim to
  /// be watching whatever happened to answer on that address.
  String get glassesHost => _store.getString(_kGlassesHost, defaultValue: '');

  Future<void> setGlassesHost(String value) =>
      _store.setString(_kGlassesHost, value.trim());

  /// The MJPEG endpoint, or null when no glasses are paired.
  Uri? get glassesStreamUri {
    final host = glassesHost;
    if (host.isEmpty) return null;
    final withScheme = host.startsWith('http') ? host : 'http://$host';
    return Uri.tryParse('$withScheme/stream');
  }

  /// Puts every account-scoped preference back to its default.
  ///
  /// These live in one device-wide Hive box with no user in the key, so they
  /// carried across a sign-out: the next account inherited the previous
  /// account's auto-SOS sensitivity, countdown length, evidence auto-record
  /// setting and biometric-unlock choice. Threat threshold is the sharpest
  /// of those -- it is synced to the server per user and decides when an
  /// automatic alarm is raised, so inheriting a stranger's value silently
  /// changes when this account gets help.
  ///
  /// Dark mode is deliberately left alone: it is a property of the phone and
  /// the person holding it, not of the account, and resetting the theme on
  /// every sign-out would read as a bug. The onboarding flag is left for the
  /// same reason.
  Future<void> clearAccountScoped() async {
    await _store.setDouble(_kThreatThreshold, 0.75);
    await _store.setInt(_kCountdownSeconds, kDefaultCountdownSeconds);
    await _store.setBool(_kAutoRecord, true);
    await _store.setBool(_kBiometric, false);
  }

  Future<void> setBiometricEnabled(bool value) => _store.setBool(_kBiometric, value);
}

@riverpod
AppPreferences appPreferences(Ref ref) => AppPreferences(ref.watch(localKeyValueStoreProvider));
