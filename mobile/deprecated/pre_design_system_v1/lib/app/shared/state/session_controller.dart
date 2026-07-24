import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/secure_store.dart';
import '../../features/auth/data/auth_repository.dart';
import '../models/domain_models.dart';

class SessionState {
  final bool initializing;
  final bool onboardingComplete;
  final bool consentAccepted;
  final bool permissionsSetupComplete;
  final bool authenticated;
  final bool loading;
  final bool firebaseReady;
  final bool biometricsEnabled;
  final ThemeMode themeMode;
  final Locale locale;
  final AppUser? user;
  final String? jwt;
  final String? pendingOtpVerificationId;
  final String? errorMessage;

  const SessionState({
    required this.initializing,
    required this.onboardingComplete,
    required this.consentAccepted,
    required this.permissionsSetupComplete,
    required this.authenticated,
    required this.loading,
    required this.firebaseReady,
    required this.biometricsEnabled,
    required this.themeMode,
    required this.locale,
    this.user,
    this.jwt,
    this.pendingOtpVerificationId,
    this.errorMessage,
  });

  factory SessionState.initial() {
    return const SessionState(
      initializing: true,
      onboardingComplete: false,
      consentAccepted: false,
      permissionsSetupComplete: false,
      authenticated: false,
      loading: false,
      firebaseReady: false,
      biometricsEnabled: false,
      themeMode: ThemeMode.system,
      locale: Locale('en'),
    );
  }

  SessionState copyWith({
    bool? initializing,
    bool? onboardingComplete,
    bool? consentAccepted,
    bool? permissionsSetupComplete,
    bool? authenticated,
    bool? loading,
    bool? firebaseReady,
    bool? biometricsEnabled,
    ThemeMode? themeMode,
    Locale? locale,
    AppUser? user,
    String? jwt,
    String? pendingOtpVerificationId,
    String? errorMessage,
    bool clearError = false,
    bool clearOtp = false,
  }) {
    return SessionState(
      initializing: initializing ?? this.initializing,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      consentAccepted: consentAccepted ?? this.consentAccepted,
      permissionsSetupComplete:
          permissionsSetupComplete ?? this.permissionsSetupComplete,
      authenticated: authenticated ?? this.authenticated,
      loading: loading ?? this.loading,
      firebaseReady: firebaseReady ?? this.firebaseReady,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      user: user ?? this.user,
      jwt: jwt ?? this.jwt,
      pendingOtpVerificationId: clearOtp
          ? null
          : pendingOtpVerificationId ?? this.pendingOtpVerificationId,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class SessionController extends StateNotifier<SessionState> {
  final AuthRepository _authRepository;
  final ApiClient _apiClient;
  final SecureStore _secureStore;
  final BiometricService _biometricService;
  final dynamic _prefs;

  SessionController({
    required AuthRepository authRepository,
    required ApiClient apiClient,
    required SecureStore secureStore,
    required BiometricService biometricService,
    required dynamic sharedPreferences,
  }) : _authRepository = authRepository,
       _apiClient = apiClient,
       _secureStore = secureStore,
       _biometricService = biometricService,
       _prefs = sharedPreferences,
       super(
         SessionState.initial().copyWith(
           firebaseReady: authRepository.firebaseReady,
         ),
       );

  Future<void> initialize() async {
    final onboarding = _prefs.getBool('onboarding_complete') ?? false;
    final consent = _prefs.getBool('privacy_consent_accepted') ?? false;
    final permissions = _prefs.getBool('permissions_setup_complete') ?? false;
    final biometrics = _prefs.getBool('biometrics_enabled') ?? false;
    final localeCode = _prefs.getString('locale_code') ?? 'en';
    final themeCode = _prefs.getString('theme_mode') ?? 'system';

    final token = await _secureStore.read(SecureStore.jwtKey);
    final userRaw = _prefs.getString('user_profile');
    final user = userRaw == null
        ? null
        : AppUser.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);

    state = state.copyWith(
      initializing: false,
      onboardingComplete: onboarding,
      consentAccepted: consent,
      permissionsSetupComplete: permissions,
      biometricsEnabled: biometrics,
      locale: Locale(localeCode),
      themeMode: _themeFromCode(themeCode),
      authenticated: token != null && user != null,
      jwt: token,
      user: user,
      clearError: true,
    );
  }

  Future<void> completeOnboarding() async {
    await _prefs.setBool('onboarding_complete', true);
    state = state.copyWith(onboardingComplete: true);
  }

  Future<void> acceptConsent(bool accepted) async {
    await _prefs.setBool('privacy_consent_accepted', accepted);
    state = state.copyWith(consentAccepted: accepted);
  }

  Future<void> completePermissionsSetup() async {
    await _prefs.setBool('permissions_setup_complete', true);
    state = state.copyWith(permissionsSetupComplete: true);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme_mode', _themeCode(mode));
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLocale(Locale locale) async {
    await _prefs.setString('locale_code', locale.languageCode);
    state = state.copyWith(locale: locale);
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await _prefs.setBool('biometrics_enabled', enabled);
    state = state.copyWith(biometricsEnabled: enabled);
  }

  Future<void> loginWithEmail({
    required String email,
    required String password,
    required AppRole role,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final authSession = await _authRepository.loginWithEmail(
        email: email,
        password: password,
        role: role,
      );
      await _persistSession(user: authSession.user, jwt: authSession.jwt);
      state = state.copyWith(
        loading: false,
        authenticated: true,
        user: authSession.user,
        jwt: authSession.jwt,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Login failed: $error',
      );
    }
  }

  Future<void> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
    required String? phone,
    required AppRole role,
  }) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final authSession = await _authRepository.signUpWithEmail(
        fullName: fullName,
        email: email,
        password: password,
        phone: phone,
        role: role,
      );
      await _persistSession(user: authSession.user, jwt: authSession.jwt);
      state = state.copyWith(
        loading: false,
        authenticated: true,
        user: authSession.user,
        jwt: authSession.jwt,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Sign up failed: $error',
      );
    }
  }

  Future<void> loginWithGoogle({required AppRole role}) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final authSession = await _authRepository.loginWithGoogle(role: role);
      await _persistSession(user: authSession.user, jwt: authSession.jwt);
      state = state.copyWith(
        loading: false,
        authenticated: true,
        user: authSession.user,
        jwt: authSession.jwt,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Google login failed: $error',
      );
    }
  }

  Future<void> startPhoneOtp(String phoneNumber) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final verificationId = await _authRepository.requestPhoneOtp(phoneNumber);
      state = state.copyWith(
        loading: false,
        pendingOtpVerificationId: verificationId,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'OTP request failed: $error',
      );
    }
  }

  Future<void> verifyPhoneOtp({
    required String smsCode,
    required AppRole role,
  }) async {
    final verificationId = state.pendingOtpVerificationId;
    if (verificationId == null) {
      state = state.copyWith(errorMessage: 'No OTP session found');
      return;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      final authSession = await _authRepository.verifyPhoneOtp(
        verificationId: verificationId,
        smsCode: smsCode,
        role: role,
      );
      await _persistSession(user: authSession.user, jwt: authSession.jwt);
      state = state.copyWith(
        loading: false,
        authenticated: true,
        user: authSession.user,
        jwt: authSession.jwt,
        clearOtp: true,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'OTP verification failed: $error',
      );
    }
  }

  Future<void> requestPasswordReset(String email) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      await _authRepository.requestPasswordReset(email);
      state = state.copyWith(loading: false);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Reset request failed: $error',
      );
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    if (!state.biometricsEnabled) {
      return false;
    }

    final success = await _biometricService.authenticate(
      reason: 'Use biometrics to unlock SafeHer',
    );
    if (!success) {
      return false;
    }

    final token = await _secureStore.read(SecureStore.jwtKey);
    final raw = _prefs.getString('user_profile');
    if (token == null || raw == null) {
      return false;
    }

    state = state.copyWith(
      authenticated: true,
      jwt: token,
      user: AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>),
    );
    return true;
  }

  Future<void> logout() async {
    await _authRepository.logout();

    await _secureStore.clearAuth();
    await _prefs.remove('user_profile');
    state = state.copyWith(
      authenticated: false,
      user: null,
      jwt: null,
      clearError: true,
      clearOtp: true,
    );
  }

  Future<void> _persistSession({
    required AppUser user,
    required String jwt,
  }) async {
    await _secureStore.write(SecureStore.jwtKey, jwt);
    await _secureStore.write(SecureStore.userIdKey, user.id);
    await _prefs.setString('user_profile', jsonEncode(user.toJson()));
    await _apiClient.refreshAuthHeaderFromStore();
  }

  ThemeMode _themeFromCode(String code) {
    return switch (code) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _themeCode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}
