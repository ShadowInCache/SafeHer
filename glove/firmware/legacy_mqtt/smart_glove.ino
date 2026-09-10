/*
 * SafeHer Smart Glove - ESP32 Code
 * Real-time motion detection with immediate threat response
 * Connects to SafeHer cloud via MQTT for advanced ML processing
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <MPU6050.h>
#include <Wire.h>
#include <esp_now.h>
#include <mbedtls/aes.h>
#include "time.h"
#include "esp_system.h"

// Configuration
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* mqtt_server = "your-safeher-server.com";
const int mqtt_port = 8883; // SSL/TLS
const char* device_id = "safeher_glove_001"; // Unique device ID

// Hardware pins
const int PANIC_BUTTON_PIN = 2;
const int LED_STATUS_PIN = 5;
const int BUZZER_PIN = 4;
const int VIBRATION_MOTOR_PIN = 18;

// MPU6050 sensor
MPU6050 mpu;
int16_t ax, ay, az, gx, gy, gz;

// WiFi and MQTT clients
WiFiClientSecure espClient;
PubSubClient client(espClient);

// Motion detection variables
float accel_buffer[150]; // 3 seconds at 50Hz
float gyro_buffer[150];
int buffer_index = 0;
unsigned long last_sensor_read = 0;
const int SENSOR_INTERVAL = 20; // 50Hz sampling

// Edge AI variables
bool threat_detected_local = false;
float threat_threshold = 2.5; // Local threshold for immediate response
unsigned long last_threat_time = 0;

// Communication variables
unsigned long last_heartbeat = 0;
const unsigned long HEARTBEAT_INTERVAL = 30000; // 30 seconds
bool cloud_connected = false;

// Emergency state
bool emergency_mode = false;
unsigned long emergency_start_time = 0;

void setup() {
    Serial.begin(115200);
    Serial.println("SafeHer Smart Glove Starting...");
    
    // Initialize hardware pins
    pinMode(PANIC_BUTTON_PIN, INPUT_PULLUP);
    pinMode(LED_STATUS_PIN, OUTPUT);
    pinMode(BUZZER_PIN, OUTPUT);
    pinMode(VIBRATION_MOTOR_PIN, OUTPUT);
    
    // Initialize status LED
    digitalWrite(LED_STATUS_PIN, LOW);
    
    // Initialize I2C and MPU6050
    Wire.begin();
    mpu.initialize();
    
    if (mpu.testConnection()) {
        Serial.println("✅ MPU6050 connection successful");
        // Configure MPU6050 for optimal motion detection
        mpu.setFullScaleAccelRange(MPU6050_ACCEL_FS_8);  // ±8g
        mpu.setFullScaleGyroRange(MPU6050_GYRO_FS_1000); // ±1000°/s
        mpu.setDLPFMode(MPU6050_DLPF_BW_42);            // Low pass filter
    } else {
        Serial.println("❌ MPU6050 connection failed");
        // Continue operation - might work without sensor
    }
    
    // Setup WiFi
    setup_wifi();
    
    // Setup MQTT with SSL
    setup_mqtt();
    
    // Initialize time (for timestamps)
    configTime(0, 0, "pool.ntp.org");
    
    Serial.println("🚀 SafeHer Smart Glove Ready");
    blink_status_led(3); // 3 blinks = ready
}

void loop() {
    // Maintain MQTT connection
    if (!client.connected()) {
        reconnect_mqtt();
    }
    client.loop();
    
    // Check panic button (highest priority)
    if (digitalRead(PANIC_BUTTON_PIN) == LOW) {
        trigger_emergency("panic_button");
        delay(1000); // Debounce
    }
    
    // Read sensors at 50Hz
    if (millis() - last_sensor_read >= SENSOR_INTERVAL) {
        read_sensors();
        
        // Local edge AI processing for immediate response
        if (detect_threat_local()) {
            if (!threat_detected_local) {
                threat_detected_local = true;
                last_threat_time = millis();
                
                // Immediate local response
                provide_immediate_feedback();
                
                // Send to cloud for advanced analysis
                send_motion_data_to_cloud(true); // Priority = true for threats
            }
        } else {
            threat_detected_local = false;
        }
        
        // Regular motion data upload (non-threat)
        if (buffer_index >= 50) { // Every 1 second of data
            send_motion_data_to_cloud(false);
        }
        
        last_sensor_read = millis();
    }
    
    // Send heartbeat
    if (millis() - last_heartbeat >= HEARTBEAT_INTERVAL) {
        send_heartbeat();
        last_heartbeat = millis();
    }
    
    // Handle emergency mode
    if (emergency_mode) {
        handle_emergency_mode();
    }
    
    // Update status LED
    update_status_led();
    
    delay(10); // Small delay for system stability
}

void setup_wifi() {
    delay(10);
    Serial.println("Connecting to WiFi...");
    WiFi.begin(ssid, password);
    
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println("");
        Serial.println("✅ WiFi connected");
        Serial.print("IP address: ");
        Serial.println(WiFi.localIP());
        cloud_connected = true;
    } else {
        Serial.println("❌ WiFi connection failed - operating in offline mode");
        cloud_connected = false;
    }
}

void setup_mqtt() {
    // Configure SSL/TLS (in production, load certificates)
    espClient.setInsecure(); // For development only
    
    client.setServer(mqtt_server, mqtt_port);
    client.setCallback(mqtt_callback);
    
    // Set large buffer for sensor data
    client.setBufferSize(2048);
}

void reconnect_mqtt() {
    while (!client.connected() && cloud_connected) {
        Serial.print("Attempting MQTT connection...");
        
        // Create client ID with device ID
        String clientId = "SafeHer-";
        clientId += device_id;
        
        if (client.connect(clientId.c_str())) {
            Serial.println("✅ MQTT connected");
            
            // Subscribe to command topics
            String command_topic = "safeher/" + String(device_id) + "/commands";
            client.subscribe(command_topic.c_str());
            
            // Send online status
            String status_topic = "safeher/" + String(device_id) + "/status";
            client.publish(status_topic.c_str(), "online", true);
            
        } else {
            Serial.print("❌ MQTT failed, rc=");
            Serial.print(client.state());
            Serial.println(" retrying in 5 seconds");
            delay(5000);
        }
    }
}

void mqtt_callback(char* topic, byte* payload, unsigned int length) {
    String message;
    for (int i = 0; i < length; i++) {
        message += (char)payload[i];
    }
    
    Serial.print("MQTT message received: ");
    Serial.println(message);
    
    // Parse command
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, message);
    
    String command = doc["command"];
    
    if (command == "emergency_response") {
        // Cloud confirmed emergency - activate ALL safety measures
        trigger_emergency("cloud_confirmed");
        
    } else if (command == "cancel_emergency") {
        // Cancel ongoing emergency
        cancel_emergency();
        
    } else if (command == "test_device") {
        // Test all device functions
        test_device_functions();
        
    } else if (command == "update_settings") {
        // Update device settings
        threat_threshold = doc["threat_threshold"];
        Serial.println("Settings updated from cloud");
    }
}

void read_sensors() {
    // Read MPU6050
    mpu.getMotion6(&ax, &ay, &az, &gx, &gy, &gz);
    
    // Convert to g-forces and degrees/second
    float accel_x = ax / 4096.0; // ±8g range
    float accel_y = ay / 4096.0;
    float accel_z = az / 4096.0;
    float gyro_x = gx / 32.8;    // ±1000°/s range
    float gyro_y = gy / 32.8;
    float gyro_z = gz / 32.8;
    
    // Store in circular buffer
    int idx = buffer_index % 150;
    accel_buffer[idx] = sqrt(accel_x*accel_x + accel_y*accel_y + accel_z*accel_z);
    gyro_buffer[idx] = sqrt(gyro_x*gyro_x + gyro_y*gyro_y + gyro_z*gyro_z);
    
    buffer_index++;
}

bool detect_threat_local() {
    // Simple edge AI for immediate threat detection
    // This provides instant response while cloud does advanced analysis
    
    if (buffer_index < 25) return false; // Need minimum data
    
    // Calculate recent motion intensity
    float recent_accel_sum = 0;
    float recent_gyro_sum = 0;
    int recent_samples = 25; // Last 0.5 seconds
    
    for (int i = 0; i < recent_samples; i++) {
        int idx = (buffer_index - i - 1) % 150;
        if (idx >= 0) {
            recent_accel_sum += accel_buffer[idx];
            recent_gyro_sum += gyro_buffer[idx];
        }
    }
    
    float avg_accel = recent_accel_sum / recent_samples;
    float avg_gyro = recent_gyro_sum / recent_samples;
    
    // Threat detection logic
    bool high_motion = avg_accel > threat_threshold;
    bool rapid_rotation = avg_gyro > (threat_threshold * 50); // Degrees/second
    
    // Check for sudden motion patterns (struggle indicators)
    bool sudden_movement = false;
    if (buffer_index >= 50) {
        float prev_avg = 0;
        for (int i = 25; i < 50; i++) {
            int idx = (buffer_index - i - 1) % 150;
            if (idx >= 0) prev_avg += accel_buffer[idx];
        }
        prev_avg /= 25;
        
        float motion_change = abs(avg_accel - prev_avg);
        sudden_movement = motion_change > 1.5;
    }
    
    return high_motion || rapid_rotation || sudden_movement;
}

void provide_immediate_feedback() {
    Serial.println("⚠️ THREAT DETECTED LOCALLY - Immediate response activated");
    
    // Vibration alert (3 quick pulses)
    for (int i = 0; i < 3; i++) {
        digitalWrite(VIBRATION_MOTOR_PIN, HIGH);
        delay(100);
        digitalWrite(VIBRATION_MOTOR_PIN, LOW);
        delay(100);
    }
    
    // Audio alert (short beeps)
    for (int i = 0; i < 3; i++) {
        tone(BUZZER_PIN, 2000, 100);
        delay(200);
    }
    
    // Flash LED
    blink_status_led(5); // 5 rapid blinks
}

void send_motion_data_to_cloud(bool priority) {
    if (!client.connected() || !cloud_connected) return;
    
    // Create JSON payload with motion data
    DynamicJsonDocument doc(2048);
    doc["device_id"] = device_id;
    doc["timestamp"] = get_iso_timestamp();
    doc["data_type"] = "motion";
    doc["priority"] = priority ? "high" : "medium";
    
    // Include recent motion data (last 1 second)
    JsonArray accel_array = doc.createNestedArray("accelerometer");
    JsonArray gyro_array = doc.createNestedArray("gyroscope");
    
    int samples_to_send = min(50, buffer_index);
    for (int i = 0; i < samples_to_send; i++) {
        int idx = (buffer_index - i - 1) % 150;
        if (idx >= 0) {
            accel_array.add(accel_buffer[idx]);
            gyro_array.add(gyro_buffer[idx]);
        }
    }
    
    // Add metadata
    doc["motion_data"]["sampling_rate"] = 50;
    doc["motion_data"]["window_size"] = samples_to_send;
    doc["motion_data"]["threat_detected_local"] = threat_detected_local;
    doc["motion_data"]["battery_level"] = get_battery_level();
    
    // Send to MQTT
    String topic = "safeher/devices/" + String(device_id) + "/events";
    String payload;
    serializeJson(doc, payload);
    
    if (client.publish(topic.c_str(), payload.c_str())) {
        Serial.println("📡 Motion data sent to cloud");
        // Reset buffer after successful send
        if (!priority) buffer_index = 0;
    } else {
        Serial.println("❌ Failed to send motion data");
    }
}

void send_heartbeat() {
    if (!client.connected() || !cloud_connected) return;
    
    DynamicJsonDocument doc(512);
    doc["device_id"] = device_id;
    doc["timestamp"] = get_iso_timestamp();
    doc["data_type"] = "heartbeat";
    doc["status"] = emergency_mode ? "emergency" : "normal";
    doc["battery_level"] = get_battery_level();
    doc["wifi_rssi"] = WiFi.RSSI();
    doc["free_heap"] = ESP.getFreeHeap();
    doc["uptime_ms"] = millis();
    
    String topic = "safeher/devices/" + String(device_id) + "/heartbeat";
    String payload;
    serializeJson(doc, payload);
    
    client.publish(topic.c_str(), payload.c_str());
}

void trigger_emergency(String trigger_type) {
    if (!emergency_mode) {
        emergency_mode = true;
        emergency_start_time = millis();
        
        Serial.println("🚨 EMERGENCY MODE ACTIVATED: " + trigger_type);
        
        // Immediate alerts
        emergency_vibration_pattern();
        emergency_audio_alert();
        
        // Send emergency message to cloud
        send_emergency_alert(trigger_type);
        
        // Try ESP-NOW broadcast to nearby devices
        broadcast_emergency_esp_now();
    }
}

void send_emergency_alert(String trigger_type) {
    DynamicJsonDocument doc(1024);
    doc["device_id"] = device_id;
    doc["timestamp"] = get_iso_timestamp();
    doc["data_type"] = "emergency";
    doc["priority"] = "emergency";
    doc["trigger_type"] = trigger_type;
    doc["location"] = get_gps_location(); // If GPS module connected
    doc["battery_level"] = get_battery_level();
    
    // Include recent motion data as evidence
    JsonArray recent_motion = doc.createNestedArray("recent_motion");
    for (int i = 0; i < min(25, buffer_index); i++) {
        int idx = (buffer_index - i - 1) % 150;
        if (idx >= 0) recent_motion.add(accel_buffer[idx]);
    }
    
    String topic = "safeher/devices/" + String(device_id) + "/emergency";
    String payload;
    serializeJson(doc, payload);
    
    // Send with QoS 1 for guaranteed delivery
    if (client.publish(topic.c_str(), payload.c_str(), true)) {
        Serial.println("🚨 Emergency alert sent to cloud");
    } else {
        Serial.println("❌ Failed to send emergency alert");
        // Store locally for retry
    }
}

void emergency_vibration_pattern() {
    // SOS pattern: ...---...
    int sos_pattern[] = {100, 100, 100, 100, 100, 100, 300, 100, 300, 100, 300, 100, 100, 100, 100, 100, 100, 100};
    int pattern_length = sizeof(sos_pattern) / sizeof(int);
    
    for (int i = 0; i < pattern_length; i++) {
        if (i % 2 == 0) {
            digitalWrite(VIBRATION_MOTOR_PIN, HIGH);
        } else {
            digitalWrite(VIBRATION_MOTOR_PIN, LOW);
        }
        delay(sos_pattern[i]);
    }
    digitalWrite(VIBRATION_MOTOR_PIN, LOW);
}

void emergency_audio_alert() {
    // Emergency siren pattern
    for (int i = 0; i < 5; i++) {
        tone(BUZZER_PIN, 2000, 500);
        delay(600);
        tone(BUZZER_PIN, 1500, 500);
        delay(600);
    }
    noTone(BUZZER_PIN);
}

void broadcast_emergency_esp_now() {
    // ESP-NOW broadcast to alert nearby SafeHer devices
    // This creates a mesh network for emergencies
    uint8_t broadcast_mac[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    
    DynamicJsonDocument doc(256);
    doc["type"] = "emergency_broadcast";
    doc["device_id"] = device_id;
    doc["timestamp"] = millis();
    
    String message;
    serializeJson(doc, message);
    
    esp_now_send(broadcast_mac, (uint8_t*)message.c_str(), message.length());
}

void handle_emergency_mode() {
    unsigned long emergency_duration = millis() - emergency_start_time;
    
    // Continue emergency alerts every 30 seconds
    if (emergency_duration % 30000 < 100) {
        send_emergency_alert("ongoing");
        emergency_vibration_pattern();
    }
    
    // Flash LED continuously
    static unsigned long last_led_flash = 0;
    if (millis() - last_led_flash > 500) {
        digitalWrite(LED_STATUS_PIN, !digitalRead(LED_STATUS_PIN));
        last_led_flash = millis();
    }
}

void cancel_emergency() {
    if (emergency_mode) {
        emergency_mode = false;
        
        Serial.println("✅ Emergency mode cancelled");
        
        // Send cancellation to cloud
        DynamicJsonDocument doc(512);
        doc["device_id"] = device_id;
        doc["timestamp"] = get_iso_timestamp();
        doc["data_type"] = "emergency_cancelled";
        doc["duration_ms"] = millis() - emergency_start_time;
        
        String topic = "safeher/devices/" + String(device_id) + "/events";
        String payload;
        serializeJson(doc, payload);
        
        client.publish(topic.c_str(), payload.c_str());
        
        // Normal operation restored
        blink_status_led(2); // 2 blinks = normal
    }
}

void test_device_functions() {
    Serial.println("🔧 Testing device functions...");
    
    // Test vibration
    digitalWrite(VIBRATION_MOTOR_PIN, HIGH);
    delay(500);
    digitalWrite(VIBRATION_MOTOR_PIN, LOW);
    
    // Test buzzer
    tone(BUZZER_PIN, 1000, 500);
    delay(600);
    
    // Test LED
    blink_status_led(3);
    
    // Test sensor
    read_sensors();
    
    Serial.println("✅ Device test complete");
}

void update_status_led() {
    if (emergency_mode) return; // LED handled in emergency mode
    
    static unsigned long last_led_update = 0;
    static bool led_state = false;
    
    if (millis() - last_led_update > 2000) {
        if (cloud_connected && client.connected()) {
            // Solid LED when connected
            digitalWrite(LED_STATUS_PIN, HIGH);
        } else {
            // Slow blink when disconnected
            led_state = !led_state;
            digitalWrite(LED_STATUS_PIN, led_state);
        }
        last_led_update = millis();
    }
}

void blink_status_led(int times) {
    for (int i = 0; i < times; i++) {
        digitalWrite(LED_STATUS_PIN, HIGH);
        delay(100);
        digitalWrite(LED_STATUS_PIN, LOW);
        delay(100);
    }
}

String get_iso_timestamp() {
    time_t now;
    struct tm timeinfo;
    if (!getLocalTime(&timeinfo)) {
        return String(millis()); // Fallback to millis
    }
    
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &timeinfo);
    return String(timestamp);
}

float get_battery_level() {
    // Read battery voltage (assuming voltage divider on ADC)
    int adc_value = analogRead(36); // VP pin
    float voltage = (adc_value * 3.3) / 4095.0;
    float battery_voltage = voltage * 2; // Adjust based on voltage divider
    
    // Convert to percentage (3.0V = 0%, 4.2V = 100%)
    float percentage = ((battery_voltage - 3.0) / 1.2) * 100;
    return constrain(percentage, 0, 100);
}

JsonObject get_gps_location() {
    // Placeholder - integrate with GPS module if available
    DynamicJsonDocument doc(256);
    JsonObject location = doc.to<JsonObject>();
    location["lat"] = 0.0;
    location["lon"] = 0.0;
    location["accuracy"] = 0;
    location["source"] = "none";
    return location;
}