package io.github.akshayag.safeher.hardware

object SafeHerHardwareContract {
    const val METHOD_CHANNEL = "safeher.example.com/hardware/methods"
    const val EVENT_CHANNEL = "safeher.example.com/hardware/events"

    object Methods {
        const val START_BLE_SCAN = "startBleScan"
        const val STOP_BLE_SCAN = "stopBleScan"
        const val CONNECT_DEVICE = "connectDevice"
        const val DISCONNECT_DEVICE = "disconnectDevice"
        const val START_BACKGROUND_MONITORING = "startBackgroundMonitoring"
        const val STOP_BACKGROUND_MONITORING = "stopBackgroundMonitoring"
        const val TRIGGER_EMERGENCY_SOS = "triggerEmergencySos"
    }

    object Events {
        const val BLE_DEVICE_FOUND = "bleDeviceFound"
        const val BLE_DEVICE_CONNECTION_STATE = "bleDeviceConnectionState"
        const val SENSOR_DATA_UPDATE = "sensorDataUpdate"
        const val PANIC_BUTTON_PRESSED = "panicButtonPressed"
        const val BACKGROUND_MONITORING_STATE = "backgroundMonitoringState"
    }

    object Args {
        const val DEVICE_ID = "deviceId"
        const val DEVICE_NAME = "deviceName"
        const val RSSI = "rssi"
        const val AUTH_SECRET = "authSecret"
        const val REASON = "reason"
        const val PAYLOAD = "payload"
    }
}
