import 'dart:async';

import 'package:flutter/services.dart';

class HardwareChannelEvent {
  final String type;
  final Map<String, dynamic> payload;

  const HardwareChannelEvent({required this.type, required this.payload});
}

class HardwareChannelGateway {
  static const _methodChannelName = 'safeher.example.com/hardware/methods';
  static const _eventChannelName = 'safeher.example.com/hardware/events';

  static const String _startBleScan = 'startBleScan';
  static const String _stopBleScan = 'stopBleScan';
  static const String _connectDevice = 'connectDevice';
  static const String _disconnectDevice = 'disconnectDevice';
  static const String _startBackgroundMonitoring = 'startBackgroundMonitoring';
  static const String _stopBackgroundMonitoring = 'stopBackgroundMonitoring';
  static const String _triggerEmergencySos = 'triggerEmergencySos';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<HardwareChannelEvent> _eventsController;
  StreamSubscription<dynamic>? _eventSubscription;

  HardwareChannelGateway({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel(_methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(_eventChannelName),
       _eventsController = StreamController<HardwareChannelEvent>.broadcast() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) {
        return;
      }
      final typedEvent = event.cast<Object?, Object?>();
      final type = (typedEvent['type'] ?? 'unknown').toString();
      final payload = switch (typedEvent['payload']) {
        Map value => value.cast<String, dynamic>(),
        _ => <String, dynamic>{},
      };
      _eventsController.add(HardwareChannelEvent(type: type, payload: payload));
    });
  }

  Stream<HardwareChannelEvent> get events => _eventsController.stream;

  Future<Map<String, dynamic>> startBleScan({int timeoutMs = 10000}) {
    return _invoke(_startBleScan, {'timeoutMs': timeoutMs});
  }

  Future<Map<String, dynamic>> stopBleScan() {
    return _invoke(_stopBleScan);
  }

  Future<Map<String, dynamic>> connectDevice({
    required String deviceId,
    String? authSecret,
  }) {
    return _invoke(_connectDevice, {
      'deviceId': deviceId,
      if (authSecret != null && authSecret.isNotEmpty) 'authSecret': authSecret,
    });
  }

  Future<Map<String, dynamic>> disconnectDevice({required String deviceId}) {
    return _invoke(_disconnectDevice, {'deviceId': deviceId});
  }

  Future<Map<String, dynamic>> startBackgroundMonitoring() {
    return _invoke(_startBackgroundMonitoring);
  }

  Future<Map<String, dynamic>> stopBackgroundMonitoring() {
    return _invoke(_stopBackgroundMonitoring);
  }

  Future<Map<String, dynamic>> triggerEmergencySos({String reason = 'manual'}) {
    return _invoke(_triggerEmergencySos, {'reason': reason});
  }

  Future<Map<String, dynamic>> _invoke(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    final dynamic result = await _methodChannel.invokeMethod<dynamic>(
      method,
      args,
    );

    if (result is Map) {
      return result.cast<String, dynamic>();
    }

    return {'status': 'ok', 'method': method, 'result': result};
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _eventsController.close();
  }
}
