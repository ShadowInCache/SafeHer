import 'package:flutter/foundation.dart';

enum AppFlavor { development, staging, production }

class AppEnvironment {
  final AppFlavor flavor;
  final String apiBaseUrl;
  final String websocketBaseUrl;
  final String mqttHost;
  final int mqttPort;
  final bool enableVerboseLogs;
  final bool useMockServices;

  const AppEnvironment({
    required this.flavor,
    required this.apiBaseUrl,
    required this.websocketBaseUrl,
    required this.mqttHost,
    required this.mqttPort,
    required this.enableVerboseLogs,
    required this.useMockServices,
  });

  factory AppEnvironment.fromDefines() {
    const flavorRaw = String.fromEnvironment(
      'APP_FLAVOR',
      defaultValue: 'development',
    );
    const apiBaseOverride = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    const wsBaseOverride = String.fromEnvironment(
      'WS_BASE_URL',
      defaultValue: '',
    );
    const mqttHostOverride = String.fromEnvironment(
      'MQTT_HOST',
      defaultValue: '',
    );
    const mqttPort = int.fromEnvironment('MQTT_PORT', defaultValue: 1883);

    final host = _defaultHostForPlatform();
    final apiBase = apiBaseOverride.isNotEmpty
        ? apiBaseOverride
        : 'http://$host:5000/api/v1';
    final wsBase = wsBaseOverride.isNotEmpty
        ? wsBaseOverride
        : 'ws://$host:5000/api/v1/ws/alerts';
    final mqttHost = mqttHostOverride.isNotEmpty ? mqttHostOverride : host;

    final flavor = switch (flavorRaw.toLowerCase()) {
      'prod' || 'production' => AppFlavor.production,
      'stage' || 'staging' => AppFlavor.staging,
      _ => AppFlavor.development,
    };

    final isProd = flavor == AppFlavor.production;

    return AppEnvironment(
      flavor: flavor,
      apiBaseUrl: apiBase,
      websocketBaseUrl: wsBase,
      mqttHost: mqttHost,
      mqttPort: mqttPort,
      enableVerboseLogs: !isProd,
      useMockServices: false,
    );
  }

  static String _defaultHostForPlatform() {
    if (kIsWeb) {
      return 'localhost';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => '10.0.2.2',
      _ => 'localhost',
    };
  }

  bool get isProduction => flavor == AppFlavor.production;
  bool get isStaging => flavor == AppFlavor.staging;
  bool get isDevelopment => flavor == AppFlavor.development;
}
