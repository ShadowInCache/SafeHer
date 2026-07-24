import 'package:flutter_test/flutter_test.dart';
import 'package:safeher_app/app/core/realtime/realtime_gateways.dart';

void main() {
  test('WebSocketGateway send before connect does not throw', () async {
    final gateway = WebSocketGateway();

    expect(
      () => gateway.send(type: 'heartbeat', payload: {'ping': true}),
      returnsNormally,
    );

    await gateway.dispose();
  });

  test(
    'MQTTGateway publish and subscribe before connect do not throw',
    () async {
      final gateway = MQTTGateway();

      expect(() => gateway.subscribe('safeher/test/#'), returnsNormally);
      expect(
        () => gateway.publish('safeher/test', {'status': 'ok'}),
        returnsNormally,
      );

      await gateway.dispose();
    },
  );
}
