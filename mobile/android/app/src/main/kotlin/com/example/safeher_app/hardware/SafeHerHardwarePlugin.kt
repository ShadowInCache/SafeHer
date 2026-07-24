package com.example.safeher_app.hardware

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SafeHerHardwarePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(
            binding.binaryMessenger,
            SafeHerHardwareContract.METHOD_CHANNEL,
        ).also { it.setMethodCallHandler(this) }

        eventChannel = EventChannel(
            binding.binaryMessenger,
            SafeHerHardwareContract.EVENT_CHANNEL,
        ).also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            SafeHerHardwareContract.Methods.START_BLE_SCAN,
            SafeHerHardwareContract.Methods.STOP_BLE_SCAN,
            SafeHerHardwareContract.Methods.CONNECT_DEVICE,
            SafeHerHardwareContract.Methods.DISCONNECT_DEVICE,
            SafeHerHardwareContract.Methods.START_BACKGROUND_MONITORING,
            SafeHerHardwareContract.Methods.STOP_BACKGROUND_MONITORING,
            SafeHerHardwareContract.Methods.TRIGGER_EMERGENCY_SOS -> {
                // Contract-first stub for native implementation phase.
                result.success(mapOf("status" to "not_implemented", "method" to call.method))
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun emit(eventType: String, payload: Map<String, Any?>) {
        eventSink?.success(
            mapOf(
                "type" to eventType,
                "payload" to payload,
            ),
        )
    }
}
