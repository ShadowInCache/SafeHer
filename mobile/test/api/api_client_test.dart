import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safeher_app/app/core/config/app_environment.dart';
import 'package:safeher_app/app/core/network/api_client.dart';
import 'package:safeher_app/app/core/network/api_exception.dart';
import 'package:safeher_app/app/core/services/secure_store.dart';

const _environment = AppEnvironment(
  flavor: AppFlavor.development,
  apiBaseUrl: 'https://api.safeher.test',
  websocketBaseUrl: 'wss://api.safeher.test/ws',
  mqttHost: 'mqtt.safeher.test',
  mqttPort: 1883,
  enableVerboseLogs: true,
  useMockServices: true,
);

void main() {
  group('ApiClient', () {
    test('decodes successful JSON maps', () async {
      final client = ApiClient(
        environment: _environment,
        secureStore: SecureStore(),
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://api.safeher.test/health');
          return http.Response('{"ok": true}', 200);
        }),
      );

      final response = await client.get('/health', authenticated: false);
      expect(response['ok'], isTrue);
    });

    test('retries transient 5xx responses', () async {
      var attempts = 0;
      final client = ApiClient(
        environment: _environment,
        secureStore: SecureStore(),
        client: MockClient((_) async {
          attempts++;
          if (attempts < 3) {
            return http.Response('{"message":"temporarily unavailable"}', 500);
          }
          return http.Response('{"status":"ready"}', 200);
        }),
      );

      final response = await client.get('/status', authenticated: false);
      expect(response['status'], 'ready');
      expect(attempts, 3);
    });

    test('throws ApiException for non-success responses', () async {
      final client = ApiClient(
        environment: _environment,
        secureStore: SecureStore(),
        client: MockClient((_) async {
          return http.Response('{"message":"Unauthorized"}', 401);
        }),
      );

      await expectLater(
        client.get('/protected', authenticated: false),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.message,
                'message',
                contains('Unauthorized'),
              ),
        ),
      );
    });
  });
}
