// SafeHer glasses — MJPEG video stream for the phone's weapon detector.
//
// Board:  Seeed XIAO ESP32-S3 Sense (camera + PSRAM)
// Serves: GET /stream   multipart/x-mixed-replace MJPEG
//         GET /status   JSON identity + battery, used for pairing
//         mDNS          safeher-glasses.local
//
// ---------------------------------------------------------------------------
// WHY THIS EXISTS AND WHAT IT REPLACES
// ---------------------------------------------------------------------------
// The previous sketch captured stills and emailed them over SMTP, then called
// WiFi.disconnect(true) so it could listen on the microphone in peace. Neither
// half is usable by the app: it needs a continuous stream, and it needs WiFi
// to stay up to receive one.
//
// This board does NOT run the detector. YOLOv8n needs roughly two orders of
// magnitude more compute and memory than an ESP32-S3 has — the arithmetic is
// in docs/WEAPON_INFERENCE_PLACEMENT.md. The phone scores the frames, and the
// video never leaves the phone.
//
// ---------------------------------------------------------------------------
// THREE THINGS THE APP DEPENDS ON — do not change these casually
// ---------------------------------------------------------------------------
// 1. Content-Length on EVERY part. The phone's parser uses it to find the end
//    of a frame. A part without one is skipped, and one claiming more than
//    2 MB is treated as a desynchronised stream and skipped too.
//
// 2. mDNS name "safeher-glasses". Release builds of the Android app block
//    cleartext HTTP everywhere except this one hostname. A raw IP address
//    works in debug builds and FAILS in release ones.
//
// 3. Omit battery rather than sending 0. The app treats an implausible zero as
//    absent, the same way it does the glove's heart rate: "no reading" and
//    "flat battery" must not look alike.
//
// ---------------------------------------------------------------------------
// NO SECRETS IN THIS FILE
// ---------------------------------------------------------------------------
// WiFi credentials live in secrets.h, which is gitignored. Copy
// secrets.h.example to secrets.h and fill it in. The earlier sketch had a
// Gmail app password and an Arduino IoT device key committed in the clear.
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <esp_camera.h>
#include <esp_http_server.h>

#include "secrets.h"

// ===================== CAMERA PINS — XIAO ESP32-S3 Sense ====================
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  10
#define SIOD_GPIO_NUM  40
#define SIOC_GPIO_NUM  39
#define Y9_GPIO_NUM    48
#define Y8_GPIO_NUM    11
#define Y7_GPIO_NUM    12
#define Y6_GPIO_NUM    14
#define Y5_GPIO_NUM    16
#define Y4_GPIO_NUM    18
#define Y3_GPIO_NUM    17
#define Y2_GPIO_NUM    15
#define VSYNC_GPIO_NUM 38
#define HREF_GPIO_NUM  47
#define PCLK_GPIO_NUM  13

// Battery sense. Leave undefined if the board has no divider fitted — the app
// prefers no reading to a fabricated one.
// #define BATTERY_ADC_PIN A0

static const char *FIRMWARE_VERSION = "1.0.0";
static const char *MDNS_HOSTNAME    = "safeher-glasses";
static const char *BOUNDARY         = "safeherframe";

static httpd_handle_t server = NULL;

// ============================== CAMERA ======================================
static bool startCamera() {
  camera_config_t config = {};
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;   config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;   config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;   config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;   config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;   config.pin_pclk  = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM; config.pin_href  = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn  = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;

  // JPEG straight out of the sensor. Anything else would have to be encoded
  // here or decoded on the phone, and both are wasted work.
  config.pixel_format = PIXFORMAT_JPEG;

  // VGA because the detector's input is 640x640. Sending more resolution costs
  // WiFi bandwidth and is thrown away at the resize.
  config.frame_size = FRAMESIZE_VGA;

  // Lower number = higher quality on this driver. ~12 keeps frames near
  // 30-60 kB, which is what sustains 10-15 fps over 2.4 GHz WiFi.
  config.jpeg_quality = 12;

  // Two buffers so capture and transmit overlap. With one, the sensor stalls
  // waiting for the previous frame to finish sending and the rate roughly
  // halves. Requires PSRAM, which the Sense variant has.
  config.fb_count  = 2;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (!psramFound()) {
    // Say so loudly. Without PSRAM this runs, badly, and the symptom is a
    // stuttering stream rather than an error.
    Serial.println("WARNING: no PSRAM — falling back to one buffer, expect low fps");
    config.fb_count = 1;
    config.fb_location = CAMERA_FB_IN_DRAM;
    config.frame_size = FRAMESIZE_QVGA;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("camera init failed: 0x%x\n", err);
    return false;
  }

  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    s->set_vflip(s, 1);       // glasses mount the sensor upside down
    s->set_hmirror(s, 0);
    s->set_brightness(s, 1);  // one notch up: outdoors at dusk is the case
    s->set_saturation(s, 0);
  }
  return true;
}

// ============================== BATTERY =====================================
// Returns -1 when unknown. The app omits the field entirely in that case
// rather than reporting zero.
static int batteryPercent() {
#ifdef BATTERY_ADC_PIN
  const int raw = analogRead(BATTERY_ADC_PIN);
  const float volts = (raw / 4095.0f) * 3.3f * 2.0f;   // 1:1 divider
  const float pct = (volts - 3.30f) / (4.20f - 3.30f) * 100.0f;
  if (pct < 0) return 0;
  if (pct > 100) return 100;
  return (int)pct;
#else
  return -1;
#endif
}

// ============================== HANDLERS ====================================
static esp_err_t statusHandler(httpd_req_t *req) {
  char body[192];
  const int battery = batteryPercent();

  // `device` is checked by the app during pairing. Without it, pairing would
  // succeed against anything that answers on the address — a router's admin
  // page, say — and the app would claim a camera it does not have.
  if (battery >= 0) {
    snprintf(body, sizeof(body),
             "{\"device\":\"safeher-glasses\",\"firmware\":\"%s\",\"battery\":%d}",
             FIRMWARE_VERSION, battery);
  } else {
    snprintf(body, sizeof(body),
             "{\"device\":\"safeher-glasses\",\"firmware\":\"%s\"}",
             FIRMWARE_VERSION);
  }

  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, body, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t streamHandler(httpd_req_t *req) {
  char contentType[64];
  snprintf(contentType, sizeof(contentType),
           "multipart/x-mixed-replace;boundary=%s", BOUNDARY);

  esp_err_t res = httpd_resp_set_type(req, contentType);
  if (res != ESP_OK) return res;
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "X-Framerate", "15");

  char header[128];
  while (true) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
      Serial.println("frame capture failed");
      res = ESP_FAIL;
      break;
    }

    // Boundary, then headers, then exactly Content-Length bytes. The phone's
    // parser reads the length and consumes precisely that many, so a mismatch
    // desynchronises the stream rather than dropping one frame.
    const int headerLength = snprintf(
        header, sizeof(header),
        "\r\n--%s\r\nContent-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n",
        BOUNDARY, (unsigned)fb->len);

    res = httpd_resp_send_chunk(req, header, headerLength);
    if (res == ESP_OK) {
      res = httpd_resp_send_chunk(req, (const char *)fb->buf, fb->len);
    }

    esp_camera_fb_return(fb);

    if (res != ESP_OK) {
      // The phone hung up — it disarmed, lost WiFi, or the journey ended.
      // Ordinary, and not an error worth logging on every disconnect.
      break;
    }
  }
  return res;
}

static void startServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.ctrl_port   = 32768;
  // The stream handler never returns while a client is attached, so it needs a
  // socket of its own. With the default of 4 and no headroom, a reconnecting
  // phone can find every slot held by a half-closed stream.
  config.max_open_sockets = 4;
  config.lru_purge_enable = true;
  config.recv_wait_timeout = 5;
  config.send_wait_timeout = 5;

  if (httpd_start(&server, &config) != ESP_OK) {
    Serial.println("http server failed to start");
    return;
  }

  httpd_uri_t streamUri = {
      .uri = "/stream", .method = HTTP_GET, .handler = streamHandler, .user_ctx = NULL};
  httpd_uri_t statusUri = {
      .uri = "/status", .method = HTTP_GET, .handler = statusHandler, .user_ctx = NULL};

  httpd_register_uri_handler(server, &streamUri);
  httpd_register_uri_handler(server, &statusUri);
}

// ================================ SETUP =====================================
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\nSafeHer glasses starting");

  if (!startCamera()) {
    Serial.println("halted: no camera");
    return;
  }

  // Stays connected for the life of the session. The previous sketch turned
  // WiFi off after setup; with it off there is no stream and the app reports
  // the weapon signal as absent for the whole journey.
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);            // sleep adds latency and drops frames
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("connecting to WiFi");
  uint32_t startedAt = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startedAt < 30000) {
    delay(400);
    Serial.print(".");
  }
  Serial.println();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi failed — restarting");
    ESP.restart();
  }

  // The app resolves this name. Release builds cannot reach a bare IP.
  if (MDNS.begin(MDNS_HOSTNAME)) {
    MDNS.addService("http", "tcp", 80);
    Serial.printf("mDNS: http://%s.local/\n", MDNS_HOSTNAME);
  } else {
    Serial.println("WARNING: mDNS failed — release builds will not connect");
  }

  startServer();
  Serial.printf("ready:  http://%s/stream\n", WiFi.localIP().toString().c_str());
  Serial.printf("pair with: %s.local\n", MDNS_HOSTNAME);
}

void loop() {
  // Reconnect rather than sit silently offline. A stream that stopped because
  // the router rebooted must come back on its own; nobody is going to power
  // cycle a pair of glasses mid-journey.
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost — reconnecting");
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    delay(2000);
  }
  delay(500);
}
