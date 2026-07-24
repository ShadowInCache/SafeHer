param(
  [string]$Flavor = "development",
  [string]$ApiBaseUrl = "http://10.0.2.2:5000/api/v1",
  [string]$WsBaseUrl = "ws://10.0.2.2:8765/ws",
  [string]$MqttHost = "10.0.2.2",
  [int]$MqttPort = 1883
)

$ErrorActionPreference = "Stop"

flutter run `
  --dart-define APP_FLAVOR=$Flavor `
  --dart-define API_BASE_URL=$ApiBaseUrl `
  --dart-define WS_BASE_URL=$WsBaseUrl `
  --dart-define MQTT_HOST=$MqttHost `
  --dart-define MQTT_PORT=$MqttPort
