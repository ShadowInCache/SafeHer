/*
 * SafeHer Smart Glasses/ESP32-CAM
 * Real-time video streaming with edge AI weapon detection
 * Connects to SafeHer cloud for advanced computer vision processing
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include "esp_camera.h"
#include "esp_timer.h"
#include "img_converters.h"
#include "fb_gv.h"
#include "driver/rtc_io.h"
#include <base64.h>

// Camera model - AI Thinker ESP32-CAM
#define CAMERA_MODEL_AI_THINKER

#include "camera_pins.h"

// Configuration
const char* ssid = "YOUR_WIFI_SSID";
const char* password = "YOUR_WIFI_PASSWORD";
const char* mqtt_server = "your-safeher-server.com";
const int mqtt_port = 8883; // SSL/TLS
const char* device_id = "safeher_glasses_001"; // Unique device ID

// Hardware pins
const int FLASH_LED_PIN = 4;
const int STATUS_LED_PIN = 33;
const int RECORDING_LED_PIN = 12;

// WiFi and MQTT clients
WiFiClientSecure espClient;
PubSubClient client(espClient);

// Camera variables
camera_fb_t * fb = NULL;
unsigned long last_frame_time = 0;
const int FRAME_INTERVAL = 1000; // 1 second between frames for analysis
const int EMERGENCY_FRAME_INTERVAL = 200; // 5fps during emergency

// Edge AI variables
bool threat_detected_local = false;
unsigned long last_threat_time = 0;
int consecutive_threat_frames = 0;
const int THREAT_CONFIRMATION_FRAMES = 3;

// Communication variables
unsigned long last_heartbeat = 0;
const unsigned long HEARTBEAT_INTERVAL = 30000; // 30 seconds
bool cloud_connected = false;

// Emergency state
bool emergency_mode = false;
bool recording_mode = false;
unsigned long emergency_start_time = 0;

// Image processing
size_t jpg_buf_len = 0;
uint8_t * jpg_buf = NULL;

void setup() {
    Serial.begin(115200);
    Serial.setDebugOutput(false);
    Serial.println("SafeHer Smart Glasses Starting...");
    
    // Initialize hardware pins
    pinMode(FLASH_LED_PIN, OUTPUT);
    pinMode(STATUS_LED_PIN, OUTPUT);
    pinMode(RECORDING_LED_PIN, OUTPUT);
    
    // Initialize status LEDs
    digitalWrite(STATUS_LED_PIN, LOW);
    digitalWrite(RECORDING_LED_PIN, LOW);
    
    // Initialize camera
    if (init_camera()) {
        Serial.println("✅ Camera initialization successful");
    } else {
        Serial.println("❌ Camera initialization failed");
        ESP.restart();
    }
    
    // Setup WiFi
    setup_wifi();
    
    // Setup MQTT with SSL
    setup_mqtt();
    
    // Initialize time (for timestamps)
    configTime(0, 0, "pool.ntp.org");
    
    Serial.println("🚀 SafeHer Smart Glasses Ready");
    blink_status_led(3); // 3 blinks = ready
}

void loop() {
    // Maintain MQTT connection
    if (!client.connected()) {
        reconnect_mqtt();
    }
    client.loop();
    
    // Capture and process frames
    unsigned long current_time = millis();
    int frame_interval = emergency_mode ? EMERGENCY_FRAME_INTERVAL : FRAME_INTERVAL;
    
    if (current_time - last_frame_time >= frame_interval) {
        process_camera_frame();
        last_frame_time = current_time;
    }
    
    // Send heartbeat
    if (current_time - last_heartbeat >= HEARTBEAT_INTERVAL) {
        send_heartbeat();
        last_heartbeat = current_time;
    }
    
    // Handle emergency mode
    if (emergency_mode) {
        handle_emergency_mode();
    }
    
    // Update status LEDs
    update_status_leds();
    
    delay(50); // Small delay for system stability
}

bool init_camera() {
    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = Y2_GPIO_NUM;
    config.pin_d1 = Y3_GPIO_NUM;
    config.pin_d2 = Y4_GPIO_NUM;
    config.pin_d3 = Y5_GPIO_NUM;
    config.pin_d4 = Y6_GPIO_NUM;
    config.pin_d5 = Y7_GPIO_NUM;
    config.pin_d6 = Y8_GPIO_NUM;
    config.pin_d7 = Y9_GPIO_NUM;
    config.pin_xclk = XCLK_GPIO_NUM;
    config.pin_pclk = PCLK_GPIO_NUM;
    config.pin_vsync = VSYNC_GPIO_NUM;
    config.pin_href = HREF_GPIO_NUM;
    config.pin_sscb_sda = SIOD_GPIO_NUM;
    config.pin_sscb_scl = SIOC_GPIO_NUM;
    config.pin_pwdn = PWDN_GPIO_NUM;
    config.pin_reset = RESET_GPIO_NUM;
    config.xclk_freq_hz = 20000000;
    config.pixel_format = PIXFORMAT_JPEG;
    
    // Frame size and quality
    if (psramFound()) {
        config.frame_size = FRAMESIZE_SVGA; // 800x600
        config.jpeg_quality = 10;           // Higher quality
        config.fb_count = 2;
    } else {
        config.frame_size = FRAMESIZE_CIF;  // 400x296  
        config.jpeg_quality = 12;
        config.fb_count = 1;
    }
    
    // Camera init
    esp_err_t err = esp_camera_init(&config);
    if (err != ESP_OK) {
        Serial.printf("Camera init failed with error 0x%x", err);
        return false;
    }
    
    // Get camera sensor
    sensor_t * s = esp_camera_sensor_get();
    if (s->id.PID == OV3660_PID) {
        s->set_vflip(s, 1);        // Flip vertically
        s->set_brightness(s, 1);   // Increase brightness
        s->set_saturation(s, -2);  // Decrease saturation
    }
    
    // Optimize for threat detection
    s->set_framesize(s, FRAMESIZE_SVGA);
    s->set_quality(s, 8);  // Good quality for AI analysis
    
    return true;
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
    
    // Set large buffer for image data
    client.setBufferSize(32768); // 32KB buffer
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
    
    Serial.print("MQTT command received: ");
    Serial.println(message);
    
    // Parse command
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, message);
    
    String command = doc["command"];
    
    if (command == "start_recording") {
        recording_mode = true;
        digitalWrite(RECORDING_LED_PIN, HIGH);
        Serial.println("📹 Recording mode activated");
        
    } else if (command == "stop_recording") {
        recording_mode = false;
        digitalWrite(RECORDING_LED_PIN, LOW);
        Serial.println("⏹️ Recording mode stopped");
        
    } else if (command == "emergency_response") {
        // Cloud confirmed threat - activate emergency mode
        trigger_emergency("cloud_confirmed");
        
    } else if (command == "cancel_emergency") {
        cancel_emergency();
        
    } else if (command == "flash_on") {
        digitalWrite(FLASH_LED_PIN, HIGH);
        
    } else if (command == "flash_off") {
        digitalWrite(FLASH_LED_PIN, LOW);
        
    } else if (command == "capture_photo") {
        capture_and_send_photo(true); // High priority
        
    } else if (command == "adjust_quality") {
        int quality = doc["quality"];
        adjust_camera_quality(quality);
    }
}

void process_camera_frame() {
    // Capture frame
    fb = esp_camera_fb_get();
    if (!fb) {
        Serial.println("❌ Camera capture failed");
        return;
    }
    
    // Basic edge AI processing for immediate threat detection
    bool local_threat = detect_threat_local(fb);
    
    if (local_threat) {
        consecutive_threat_frames++;
        
        if (consecutive_threat_frames >= THREAT_CONFIRMATION_FRAMES && !threat_detected_local) {
            threat_detected_local = true;
            last_threat_time = millis();
            
            Serial.println("⚠️ VISUAL THREAT DETECTED - Immediate response");
            
            // Immediate local response
            provide_immediate_feedback();
            
            // Send high-priority frame to cloud
            send_frame_to_cloud(fb, true);
        }
    } else {
        consecutive_threat_frames = 0;
        if (threat_detected_local && millis() - last_threat_time > 5000) {
            threat_detected_local = false; // Threat cleared after 5 seconds
        }
    }
    
    // Regular frame processing
    if (!threat_detected_local && !emergency_mode) {
        // Send frame to cloud for analysis (lower frequency)
        static int frame_counter = 0;
        if (frame_counter % 5 == 0) { // Every 5th frame
            send_frame_to_cloud(fb, false);
        }
        frame_counter++;
    }
    
    // If in recording mode, save frame locally or send to evidence storage
    if (recording_mode || emergency_mode) {
        send_frame_to_evidence_storage(fb);
    }
    
    esp_camera_fb_return(fb);
}

bool detect_threat_local(camera_fb_t* frame) {
    // Simple edge AI for weapon detection using basic image analysis
    // This is a simplified version - cloud does sophisticated YOLO detection
    
    if (!frame || frame->len < 1000) return false;
    
    // Basic threat indicators (very simple heuristics)
    // In production, this would use a lightweight ML model
    
    // 1. Check for metallic objects (simplified brightness analysis)
    uint8_t* img_data = frame->buf;
    size_t img_len = frame->len;
    
    // Count bright pixels (potential metallic reflections)
    int bright_pixel_count = 0;
    int dark_pixel_count = 0;
    
    // Sample every 100th byte for speed
    for (size_t i = 0; i < img_len; i += 100) {
        uint8_t pixel = img_data[i];
        if (pixel > 200) bright_pixel_count++; // Very bright
        if (pixel < 50) dark_pixel_count++;    // Very dark
    }
    
    // 2. Check brightness contrast (weapons may create high contrast)
    float contrast_ratio = (float)bright_pixel_count / (dark_pixel_count + 1);
    
    // 3. Check for rapid scene changes (movement patterns)
    static uint32_t last_frame_checksum = 0;
    uint32_t current_checksum = 0;
    for (size_t i = 0; i < min(img_len, 1000); i += 10) {
        current_checksum += img_data[i];
    }
    
    float frame_change = abs((int)(current_checksum - last_frame_checksum));
    last_frame_checksum = current_checksum;
    
    // Simple threat logic (this is very basic - cloud AI is much more sophisticated)
    bool high_contrast = contrast_ratio > 2.0;
    bool rapid_change = frame_change > 500;
    bool suspicious_brightness = bright_pixel_count > 20;
    
    return high_contrast && (rapid_change || suspicious_brightness);
}

void provide_immediate_feedback() {
    // Flash LED warning
    for (int i = 0; i < 5; i++) {
        digitalWrite(FLASH_LED_PIN, HIGH);
        delay(50);
        digitalWrite(FLASH_LED_PIN, LOW);
        delay(50);
    }
    
    // Status LED rapid blink
    blink_status_led(10);
}

void send_frame_to_cloud(camera_fb_t* frame, bool priority) {
    if (!client.connected() || !cloud_connected) return;
    
    // Convert frame to base64 for transmission
    String base64_image = base64::encode(frame->buf, frame->len);
    
    // Split large images into chunks if needed
    const size_t MAX_CHUNK_SIZE = 8192; // 8KB chunks
    size_t total_chunks = (base64_image.length() + MAX_CHUNK_SIZE - 1) / MAX_CHUNK_SIZE;
    
    String frame_id = String(device_id) + "_" + String(millis());
    
    for (size_t chunk = 0; chunk < total_chunks; chunk++) {
        DynamicJsonDocument doc(10240);
        doc["device_id"] = device_id;
        doc["timestamp"] = get_iso_timestamp();
        doc["data_type"] = "vision";
        doc["priority"] = priority ? "high" : "medium";
        
        // Frame metadata
        doc["frame_id"] = frame_id;
        doc["chunk_number"] = chunk;
        doc["total_chunks"] = total_chunks;
        doc["frame_width"] = frame->width;
        doc["frame_height"] = frame->height;
        doc["frame_format"] = "jpeg";
        doc["frame_size"] = frame->len;
        doc["threat_detected_local"] = threat_detected_local;
        
        // Image data chunk
        size_t chunk_start = chunk * MAX_CHUNK_SIZE;
        size_t chunk_size = min(MAX_CHUNK_SIZE, base64_image.length() - chunk_start);
        doc["image_data"] = base64_image.substring(chunk_start, chunk_start + chunk_size);
        
        String topic = "safeher/devices/" + String(device_id) + "/events";
        String payload;
        serializeJson(doc, payload);
        
        if (client.publish(topic.c_str(), payload.c_str())) {
            Serial.printf("📡 Frame chunk %d/%d sent to cloud\n", chunk + 1, total_chunks);
        } else {
            Serial.printf("❌ Failed to send frame chunk %d\n", chunk + 1);
            break; // Stop sending if one chunk fails
        }
        
        delay(100); // Small delay between chunks
    }
}

void send_frame_to_evidence_storage(camera_fb_t* frame) {
    if (!client.connected() || !cloud_connected) return;
    
    // Send frame to evidence storage service
    String base64_image = base64::encode(frame->buf, frame->len);
    
    DynamicJsonDocument doc(2048);
    doc["device_id"] = device_id;
    doc["user_id"] = "user_" + String(device_id);
    doc["timestamp"] = get_iso_timestamp();
    doc["file_type"] = "image";
    doc["filename"] = "evidence_" + String(millis()) + ".jpg";
    doc["threat_level"] = emergency_mode ? "emergency" : "medium";
    doc["file_data"] = base64_image;
    
    String topic = "safeher/evidence/store";
    String payload;
    serializeJson(doc, payload);
    
    if (client.publish(topic.c_str(), payload.c_str())) {
        Serial.println("📁 Evidence frame stored");
    }
}

void capture_and_send_photo(bool priority) {
    fb = esp_camera_fb_get();
    if (fb) {
        send_frame_to_cloud(fb, priority);
        if (priority) {
            send_frame_to_evidence_storage(fb);
        }
        esp_camera_fb_return(fb);
    }
}

void adjust_camera_quality(int quality) {
    sensor_t * s = esp_camera_sensor_get();
    if (s) {
        s->set_quality(s, constrain(quality, 4, 63));
        Serial.printf("Camera quality adjusted to %d\n", quality);
    }
}

void send_heartbeat() {
    if (!client.connected() || !cloud_connected) return;
    
    DynamicJsonDocument doc(1024);
    doc["device_id"] = device_id;
    doc["timestamp"] = get_iso_timestamp();
    doc["data_type"] = "heartbeat";
    doc["status"] = emergency_mode ? "emergency" : (recording_mode ? "recording" : "normal");
    doc["wifi_rssi"] = WiFi.RSSI();
    doc["free_heap"] = ESP.getFreeHeap();
    doc["uptime_ms"] = millis();
    doc["camera_status"] = "active";
    doc["threat_detected"] = threat_detected_local;
    
    String topic = "safeher/devices/" + String(device_id) + "/heartbeat";
    String payload;
    serializeJson(doc, payload);
    
    client.publish(topic.c_str(), payload.c_str());
}

void trigger_emergency(String trigger_type) {
    if (!emergency_mode) {
        emergency_mode = true;
        recording_mode = true; // Auto-start recording
        emergency_start_time = millis();
        
        Serial.println("🚨 EMERGENCY MODE ACTIVATED: " + trigger_type);
        
        // Visual alerts
        digitalWrite(RECORDING_LED_PIN, HIGH);
        emergency_flash_pattern();
        
        // Send emergency alert to cloud
        send_emergency_alert(trigger_type);
        
        // Start continuous high-quality recording
        sensor_t * s = esp_camera_sensor_get();
        if (s) s->set_quality(s, 4); // Highest quality
    }
}

void send_emergency_alert(String trigger_type) {
    DynamicJsonDocument doc(1024);
    doc["device_id"] = device_id;
    doc["timestamp"] = get_iso_timestamp();
    doc["data_type"] = "emergency";
    doc["priority"] = "emergency";
    doc["trigger_type"] = trigger_type;
    doc["device_type"] = "camera";
    doc["location"] = get_gps_location();
    
    String topic = "safeher/devices/" + String(device_id) + "/emergency";
    String payload;
    serializeJson(doc, payload);
    
    if (client.publish(topic.c_str(), payload.c_str(), true)) {
        Serial.println("🚨 Emergency alert sent to cloud");
    }
}

void emergency_flash_pattern() {
    // Rapid flash pattern for emergency
    for (int i = 0; i < 20; i++) {
        digitalWrite(FLASH_LED_PIN, HIGH);
        delay(50);
        digitalWrite(FLASH_LED_PIN, LOW);
        delay(50);
    }
}

void handle_emergency_mode() {
    unsigned long emergency_duration = millis() - emergency_start_time;
    
    // Continue emergency visual alerts
    if (emergency_duration % 10000 < 100) {
        emergency_flash_pattern();
        send_emergency_alert("ongoing");
    }
    
    // Flash recording LED continuously
    static unsigned long last_record_flash = 0;
    if (millis() - last_record_flash > 300) {
        digitalWrite(RECORDING_LED_PIN, !digitalRead(RECORDING_LED_PIN));
        last_record_flash = millis();
    }
}

void cancel_emergency() {
    if (emergency_mode) {
        emergency_mode = false;
        recording_mode = false;
        
        Serial.println("✅ Emergency mode cancelled");
        
        // Turn off LEDs
        digitalWrite(RECORDING_LED_PIN, LOW);
        digitalWrite(FLASH_LED_PIN, LOW);
        
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
        
        // Reset camera quality
        sensor_t * s = esp_camera_sensor_get();
        if (s) s->set_quality(s, 10); // Normal quality
        
        blink_status_led(3); // 3 blinks = normal
    }
}

void update_status_leds() {
    if (emergency_mode) return; // LEDs handled in emergency mode
    
    static unsigned long last_led_update = 0;
    static bool led_state = false;
    
    if (millis() - last_led_update > 2000) {
        if (cloud_connected && client.connected()) {
            // Solid LED when connected
            digitalWrite(STATUS_LED_PIN, HIGH);
        } else {
            // Slow blink when disconnected
            led_state = !led_state;
            digitalWrite(STATUS_LED_PIN, led_state);
        }
        last_led_update = millis();
    }
}

void blink_status_led(int times) {
    for (int i = 0; i < times; i++) {
        digitalWrite(STATUS_LED_PIN, HIGH);
        delay(100);
        digitalWrite(STATUS_LED_PIN, LOW);
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