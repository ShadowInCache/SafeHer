// SafeHer glasses — video and audio streams for the phone.
//
// Board:  Seeed XIAO ESP32-S3 Sense (OV camera + PDM microphone + PSRAM)
//
//   GET /stream   MJPEG video      multipart/x-mixed-replace   ← app uses this
//   GET /audio    16 kHz mono WAV  streaming PCM               ← served, not yet consumed
//   GET /level    JSON loudness    cheap, no streaming
//   GET /status   JSON identity + battery, used for pairing
//   mDNS          safeher-glasses.local
//
// ---------------------------------------------------------------------------
// WHICH OF THESE THE APP ACTUALLY READS TODAY
// ---------------------------------------------------------------------------
// Video and status: yes. Audio and level: no, not yet.
//
// That is not an oversight. The app's audio threat signal runs on the PHONE's
// microphone through the platform speech recogniser, which is a better mic and
// a better recogniser than anything reachable over an I2S link, and it needs no
// network at all. Android's SpeechRecognizer also cannot be fed an arbitrary
// audio stream, so glasses audio cannot simply be substituted for it — it would
// need its own transcription path.
//
// The endpoints exist so the hardware is not the thing blocking that decision.
// See the "WHAT GLASSES AUDIO IS ACTUALLY GOOD FOR" note at the bottom.
//
// ---------------------------------------------------------------------------
// THREE THINGS THE APP DEPENDS ON — do not change these casually
// ---------------------------------------------------------------------------
// 1. Content-Length on EVERY MJPEG part. The phone's parser uses it to find the
//    end of a frame. A part without one is skipped; one claiming more than 2 MB
//    is treated as a desynchronised stream and skipped too.
//
// 2. mDNS name "safeher-glasses". Release builds of the Android app block
//    cleartext HTTP everywhere except this one hostname. A raw IP address works
//    in debug builds and FAILS in release ones.
//
// 3. Omit battery rather than sending 0. The app treats an implausible zero as
//    absent, the same way it does the glove's heart rate: "no reading" and
//    "flat battery" must not look alike.
//
// ---------------------------------------------------------------------------
// NO SECRETS IN THIS FILE
// ---------------------------------------------------------------------------
// WiFi credentials live in secrets.h, which is gitignored. Copy
// secrets.h.example to secrets.h and fill it in. The sketch this replaces had a
// Gmail app password and an Arduino IoT device key written into the source.
// ---------------------------------------------------------------------------

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <esp_camera.h>
#include <esp_http_server.h>
#include <driver/i2s_pdm.h>
#include <math.h>

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

// ===================== MICROPHONE — PDM on the Sense expansion ==============
// These two are taken from the working noise-detection sketch rather than from
// a datasheet, because they are known to work on this exact board.
#define I2S_CLK_PIN   42
#define I2S_DATA_PIN  41

// 16 kHz mono, which is what every speech model in this project expects. Going
// higher costs bandwidth and buys nothing: the models resample down to 16 kHz.
static const uint32_t AUDIO_SAMPLE_RATE = 16000;
static const size_t   AUDIO_CHUNK_SAMPLES = 512;

// Battery sense. Leave undefined if no divider is fitted — the app prefers no
// reading to a fabricated one.
// #define BATTERY_ADC_PIN A0

static const char *FIRMWARE_VERSION = "1.1.0";
static const char *MDNS_HOSTNAME    = "safeher-glasses";
static const char *BOUNDARY         = "safeherframe";

static httpd_handle_t server = NULL;
static i2s_chan_handle_t micChannel = NULL;
static bool micReady = false;

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

  // JPEG straight from the sensor. Anything else would have to be encoded here
  // or decoded on the phone, and both are wasted work.
  config.pixel_format = PIXFORMAT_JPEG;

  // VGA because the detector's input is 640x640. More resolution costs WiFi
  // bandwidth and is thrown away at the resize.
  config.frame_size = FRAMESIZE_VGA;

  // Lower number = higher quality on this driver. ~12 keeps frames near
  // 30-60 kB, which is what sustains 10-15 fps over 2.4 GHz WiFi.
  config.jpeg_quality = 12;

  // Two buffers so capture and transmit overlap. With one, the sensor stalls
  // waiting for the previous frame and the rate roughly halves.
  config.fb_count = 2;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (!psramFound()) {
    // Say so loudly. Without PSRAM this runs badly, and the symptom is a
    // stuttering stream rather than an error. Check "PSRAM: OPI PSRAM" in the
    // Arduino Tools menu.
    Serial.println("WARNING: no PSRAM — check Tools > PSRAM. Falling back.");
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
    s->set_vflip(s, 1);       // the glasses mount the sensor upside down
    s->set_hmirror(s, 0);
    s->set_brightness(s, 1);  // one notch up: outdoors at dusk is the case
    s->set_saturation(s, 0);
  }
  return true;
}

// ============================ MICROPHONE ====================================
static bool startMicrophone() {
  i2s_chan_config_t chanConfig =
      I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_AUTO, I2S_ROLE_MASTER);
  chanConfig.auto_clear = true;

  if (i2s_new_channel(&chanConfig, NULL, &micChannel) != ESP_OK) {
    Serial.println("i2s channel allocation failed");
    return false;
  }

  i2s_pdm_rx_config_t pdmConfig = {
      .clk_cfg  = I2S_PDM_RX_CLK_DEFAULT_CONFIG(AUDIO_SAMPLE_RATE),
      .slot_cfg = I2S_PDM_RX_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT,
                                                 I2S_SLOT_MODE_MONO),
      .gpio_cfg = {
          .clk = (gpio_num_t)I2S_CLK_PIN,
          .din = (gpio_num_t)I2S_DATA_PIN,
          .invert_flags = {.clk_inv = false},
      },
  };

  if (i2s_channel_init_pdm_rx_mode(micChannel, &pdmConfig) != ESP_OK) {
    Serial.println("PDM mode init failed");
    return false;
  }
  if (i2s_channel_enable(micChannel) != ESP_OK) {
    Serial.println("i2s enable failed");
    return false;
  }
  return true;
}

/// Reads one block and returns its RMS in dBFS, or -120 when nothing was read.
static float readLevelDb() {
  if (!micReady) return -120.0f;

  static int16_t samples[AUDIO_CHUNK_SAMPLES];
  size_t got = 0;
  if (i2s_channel_read(micChannel, samples, sizeof(samples), &got,
                       pdMS_TO_TICKS(200)) != ESP_OK || got == 0) {
    return -120.0f;
  }

  const size_t count = got / sizeof(int16_t);
  double sum = 0;
  for (size_t i = 0; i < count; i++) {
    const double normalised = samples[i] / 32768.0;
    sum += normalised * normalised;
  }
  const double rms = sqrt(sum / count);
  return rms > 0 ? (float)(20.0 * log10(rms)) : -120.0f;
}

// ============================== BATTERY =====================================
// Returns -1 when unknown. The app omits the field entirely in that case rather
// than reporting zero.
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
  char body[256];
  const int battery = batteryPercent();

  // `device` is checked by the app during pairing. Without it, pairing would
  // succeed against anything that answers on the address — a router's admin
  // page, say — and the app would claim a camera it does not have.
  int written = snprintf(body, sizeof(body),
      "{\"device\":\"safeher-glasses\",\"firmware\":\"%s\",\"video\":true,"
      "\"audio\":%s", FIRMWARE_VERSION, micReady ? "true" : "false");
  if (battery >= 0) {
    written += snprintf(body + written, sizeof(body) - written,
                        ",\"battery\":%d", battery);
  }
  snprintf(body + written, sizeof(body) - written, "}");

  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, body, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t levelHandler(httpd_req_t *req) {
  char body[96];
  snprintf(body, sizeof(body), "{\"level_db\":%.1f,\"available\":%s}",
           readLevelDb(), micReady ? "true" : "false");

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

    // Boundary, then headers, then exactly Content-Length bytes. The phone
    // reads the length and consumes precisely that many, so a mismatch
    // desynchronises the stream rather than dropping a single frame.
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
      // Ordinary, and not worth logging on every disconnect.
      break;
    }
  }
  return res;
}

/// Streams 16 kHz mono PCM wrapped in a WAV header of indefinite length.
///
/// The declared sizes are 0xFFFFFFFF because the length is not known in
/// advance — this is a live microphone, not a file. Every player and library
/// worth using reads until the connection closes; one that trusts the header
/// literally will try to read four gigabytes, which is the documented cost of
/// streaming WAV and the reason the endpoint is separate from /stream.
static esp_err_t audioHandler(httpd_req_t *req) {
  if (!micReady) {
    httpd_resp_send_err(req, HTTPD_500_INTERNAL_SERVER_ERROR,
                        "microphone unavailable");
    return ESP_FAIL;
  }

  httpd_resp_set_type(req, "audio/wav");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");

  const uint32_t byteRate = AUDIO_SAMPLE_RATE * 2;  // mono, 16-bit
  uint8_t wav[44] = {
      'R','I','F','F', 0xFF,0xFF,0xFF,0xFF, 'W','A','V','E',
      'f','m','t',' ', 16,0,0,0, 1,0, 1,0,
      (uint8_t)(AUDIO_SAMPLE_RATE      ), (uint8_t)(AUDIO_SAMPLE_RATE >>  8),
      (uint8_t)(AUDIO_SAMPLE_RATE >> 16), (uint8_t)(AUDIO_SAMPLE_RATE >> 24),
      (uint8_t)(byteRate      ), (uint8_t)(byteRate >>  8),
      (uint8_t)(byteRate >> 16), (uint8_t)(byteRate >> 24),
      2,0, 16,0,
      'd','a','t','a', 0xFF,0xFF,0xFF,0xFF,
  };

  esp_err_t res = httpd_resp_send_chunk(req, (const char *)wav, sizeof(wav));

  static int16_t samples[AUDIO_CHUNK_SAMPLES];
  while (res == ESP_OK) {
    size_t got = 0;
    if (i2s_channel_read(micChannel, samples, sizeof(samples), &got,
                         pdMS_TO_TICKS(500)) != ESP_OK || got == 0) {
      continue;  // a dropped block is not a reason to end the stream
    }
    res = httpd_resp_send_chunk(req, (const char *)samples, got);
  }
  return res;
}

static void startServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port = 80;
  config.ctrl_port   = 32768;

  // Both stream handlers block forever while a client is attached, so each
  // occupies a socket AND a worker for its whole life. With the default of 4
  // and two infinite handlers, a reconnecting phone finds every slot held by a
  // half-closed stream and /status stops answering — which looks to the app
  // like the glasses have vanished.
  config.max_open_sockets = 7;
  config.lru_purge_enable = true;
  config.recv_wait_timeout = 5;
  config.send_wait_timeout = 5;
  config.stack_size = 8192;

  if (httpd_start(&server, &config) != ESP_OK) {
    Serial.println("http server failed to start");
    return;
  }

  httpd_uri_t routes[] = {
      {.uri = "/stream", .method = HTTP_GET, .handler = streamHandler, .user_ctx = NULL},
      {.uri = "/audio",  .method = HTTP_GET, .handler = audioHandler,  .user_ctx = NULL},
      {.uri = "/level",  .method = HTTP_GET, .handler = levelHandler,  .user_ctx = NULL},
      {.uri = "/status", .method = HTTP_GET, .handler = statusHandler, .user_ctx = NULL},
  };
  for (auto &route : routes) httpd_register_uri_handler(server, &route);
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

  // The microphone is optional to the app today, so a failure here degrades
  // rather than halts: video is the signal that is actually consumed, and
  // losing it because the mic would not initialise would be the wrong trade.
  micReady = startMicrophone();
  Serial.printf("microphone: %s\n", micReady ? "ready" : "UNAVAILABLE");

  // Stays connected for the life of the session. The sketch this replaces
  // turned WiFi off after setup; with it off there is no stream at all and the
  // app reports the weapon signal as absent for the whole journey.
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
  Serial.printf("video:  http://%s/stream\n", WiFi.localIP().toString().c_str());
  Serial.printf("audio:  http://%s/audio\n", WiFi.localIP().toString().c_str());
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

// ---------------------------------------------------------------------------
// WHAT GLASSES AUDIO IS ACTUALLY GOOD FOR
// ---------------------------------------------------------------------------
// Not speech recognition. The phone's microphone is better placed, its
// recogniser is better, and Android's SpeechRecognizer cannot be fed a remote
// stream anyway — glasses audio would need its own transcription path, which
// today means uploading it to the server for Whisper.
//
// Two uses that do not need any of that, in rough order of value:
//
//   * EVIDENCE. Audio from the wearer's head is better positioned than a phone
//     in a bag or a pocket. Recording /audio alongside an incident costs one
//     HTTP GET and needs no model at all.
//
//   * A LOUDNESS CUE. /level is one number and no bandwidth. A shout is loud
//     long before it is intelligible, and unlike a transcript it survives wind,
//     distance and a mouth turned away. It would be supporting context, not a
//     fusion input — the score has exactly three signals by design.
//
// Both are app-side work that has not been done. The hardware is no longer the
// thing blocking it.
