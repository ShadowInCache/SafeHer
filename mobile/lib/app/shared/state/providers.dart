import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap.dart';
import '../../core/config/app_environment.dart';
import '../../core/device/hardware_channel_gateway.dart';
import '../../core/device/safety_hardware_bridge.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/data/hybrid_auth_repository.dart';
import '../../features/safety/data/hybrid_safety_repository.dart';
import '../../features/safety/data/safety_repository.dart';
import '../../features/safety/domain/use_cases/dispatch_emergency_alert_use_case.dart';
import '../../features/safety/domain/use_cases/incident_projection_use_case.dart';
import '../../features/safety/domain/use_cases/threat_assessment_use_case.dart';
import 'safety_controller.dart';
import 'session_controller.dart';

final environmentProvider = Provider<AppEnvironment>((ref) {
  throw UnimplementedError('environmentProvider must be overridden at startup');
});

final bootstrapBundleProvider = Provider<BootstrapBundle>((ref) {
  throw UnimplementedError(
    'bootstrapBundleProvider must be overridden after bootstrap',
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final bundle = ref.watch(bootstrapBundleProvider);
  return HybridAuthRepository(
    apiClient: bundle.apiClient,
    firebaseSupport: bundle.firebaseSupport,
    firebaseReady: bundle.firebaseReady,
  );
}, dependencies: [bootstrapBundleProvider]);

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  final bundle = ref.watch(bootstrapBundleProvider);
  return HybridSafetyRepository(
    localDatabaseService: bundle.localDatabaseService,
    apiClient: bundle.apiClient,
  );
}, dependencies: [bootstrapBundleProvider]);

final hardwareChannelGatewayProvider = Provider<HardwareChannelGateway?>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }

  final gateway = HardwareChannelGateway();
  ref.onDispose(() {
    gateway.dispose();
  });
  return gateway;
});

final safetyHardwareBridgeProvider = Provider<SafetyHardwareBridge>((ref) {
  final bundle = ref.watch(bootstrapBundleProvider);
  final hardwareGateway = ref.watch(hardwareChannelGatewayProvider);

  return DeviceConnectivityHardwareBridge(
    bundle.deviceConnectivityService,
    hardwareChannelGateway: hardwareGateway,
    enableNativeBridge: hardwareGateway != null,
  );
}, dependencies: [bootstrapBundleProvider, hardwareChannelGatewayProvider]);

final threatAssessmentUseCaseProvider = Provider<ThreatAssessmentUseCase>((
  ref,
) {
  return const ThreatAssessmentUseCase();
});

final incidentProjectionUseCaseProvider = Provider<IncidentProjectionUseCase>((
  ref,
) {
  return IncidentProjectionUseCase(
    threatAssessmentUseCase: ref.watch(threatAssessmentUseCaseProvider),
  );
}, dependencies: [threatAssessmentUseCaseProvider]);

final dispatchEmergencyAlertUseCaseProvider =
    Provider<DispatchEmergencyAlertUseCase>((ref) {
      final bundle = ref.watch(bootstrapBundleProvider);
      return DispatchEmergencyAlertUseCase(
        safetyRepository: ref.watch(safetyRepositoryProvider),
        webSocketGateway: bundle.webSocketGateway,
        mqttGateway: bundle.mqttGateway,
      );
    }, dependencies: [bootstrapBundleProvider, safetyRepositoryProvider]);

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      final bundle = ref.watch(bootstrapBundleProvider);
      final controller = SessionController(
        authRepository: ref.watch(authRepositoryProvider),
        apiClient: bundle.apiClient,
        secureStore: bundle.secureStore,
        biometricService: bundle.biometricService,
        sharedPreferences: bundle.sharedPreferences,
      );
      controller.initialize();
      return controller;
    }, dependencies: [bootstrapBundleProvider, authRepositoryProvider]);

final safetyControllerProvider =
    StateNotifierProvider<SafetyController, SafetyState>(
      (ref) {
        final bundle = ref.watch(bootstrapBundleProvider);
        final controller = SafetyController(
          safetyRepository: ref.watch(safetyRepositoryProvider),
          apiClient: bundle.apiClient,
          webSocketGateway: bundle.webSocketGateway,
          mqttGateway: bundle.mqttGateway,
          hardwareBridge: ref.watch(safetyHardwareBridgeProvider),
          backgroundGuardService: bundle.backgroundGuardService,
          evidenceVaultService: bundle.evidenceVaultService,
          threatAssessmentUseCase: ref.watch(threatAssessmentUseCaseProvider),
          incidentProjectionUseCase: ref.watch(
            incidentProjectionUseCaseProvider,
          ),
          dispatchEmergencyAlertUseCase: ref.watch(
            dispatchEmergencyAlertUseCaseProvider,
          ),
        );

        ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
          final userId = next.user?.id;
          final wasAuthenticated = previous?.authenticated ?? false;
          if (next.authenticated && userId != null && !wasAuthenticated) {
            controller.initialize(userId: userId);
          }
          if (!next.authenticated && wasAuthenticated) {
            controller.stopMonitoring();
          }
        });

        return controller;
      },
      dependencies: [
        bootstrapBundleProvider,
        safetyRepositoryProvider,
        safetyHardwareBridgeProvider,
        threatAssessmentUseCaseProvider,
        incidentProjectionUseCaseProvider,
        dispatchEmergencyAlertUseCaseProvider,
        sessionControllerProvider,
      ],
    );

final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(sessionControllerProvider).themeMode;
}, dependencies: [sessionControllerProvider]);

final localeProvider = Provider<Locale>((ref) {
  return ref.watch(sessionControllerProvider).locale;
}, dependencies: [sessionControllerProvider]);

final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map((results) {
    return !results.contains(ConnectivityResult.none);
  });
});
