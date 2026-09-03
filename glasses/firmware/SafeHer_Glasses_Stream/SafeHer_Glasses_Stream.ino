// SafeHer glasses — video and audio streaming for the SafeHer app.
//
// Board: Seeed XIAO ESP32-S3 Sense
//
// This is the working demo sketch with the app's contract added. The camera
// and microphone setup, the streaming task and the audio filtering are the
// ones proven on real hardware; what changed is routing, discovery and one
// endpoint. Those changes are marked "SafeHer app:" throughout.
//
//   GET /stream   MJPEG video, multipart/x-mixed-replace
//   GET /status   JSON identity — the app refuses to pair without it
//   GET /audio    streaming WAV, recorded as evidence during an emergency
//   ws://:81      raw PCM, kept for the standalone demo
//
// The board runs no model. YOLOv8n needs roughly two orders of magnitude more
// compute and memory than an ESP32-S3 has, so the phone scores the frames and
// the video never leaves it. See docs/WEAPON_INFERENCE_PLACEMENT.md.

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include "esp_camera.h"
#include "driver/i2s_pdm.h"
#include <WebSocketsServer.h>

// SafeHer app: credentials moved out of this file. Copy secrets.h.example to
// secrets.h and fill it in — secrets.h is gitignored. A `#define` in a .ino is
// published the moment the commit is, and an earlier sketch in this project
// had a Gmail app password pushed to a public repository.
#include "secrets.h"

// =====================================================
// XIAO ESP32-S3 SENSE CAMERA PINS
// =====================================================

#define PWDN_GPIO_NUM     -1
#define RESET_GPIO_NUM    -1

#define XCLK_GPIO_NUM      10

#define SIOD_GPIO_NUM      40
#define SIOC_GPIO_NUM      39

#define Y9_GPIO_NUM        48
#define Y8_GPIO_NUM        11
#define Y7_GPIO_NUM        12
#define Y6_GPIO_NUM        14
#define Y5_GPIO_NUM        16
#define Y4_GPIO_NUM        18
#define Y3_GPIO_NUM        17
#define Y2_GPIO_NUM        15

#define VSYNC_GPIO_NUM     38
#define HREF_GPIO_NUM      47
#define PCLK_GPIO_NUM      13

// =====================================================
// MICROPHONE
// =====================================================

#define I2S_CLK             42
#define I2S_DATA            41

#define SAMPLE_RATE         16000
#define AUDIO_SAMPLES       2048

// SafeHer app: advertised over mDNS under this name. Release builds of the
// Android app deny cleartext HTTP everywhere EXCEPT this hostname, so a raw IP
// address works in a debug build and fails in a release one.
static const char* MDNS_HOSTNAME    = "safeher-glasses";
static const char* FIRMWARE_VERSION = "1.2.0";

// =====================================================
// SERVERS
// =====================================================

WiFiServer videoServer(80);
WebSocketsServer audioServer(81);

// =====================================================
// MICROPHONE
// =====================================================

i2s_chan_handle_t rx_handle = NULL;

int16_t audioBuffer[AUDIO_SAMPLES];

// =====================================================
// CLIENTS
// =====================================================

WiFiClient videoClient;

// SafeHer app: a separate slot for the HTTP audio stream, so a phone recording
// evidence does not evict the video client and vice versa.
WiFiClient audioHttpClient;

// =====================================================
// CAMERA INITIALIZATION
// =====================================================

void startCamera() {

  camera_config_t config;

  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;

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
  config.pin_href  = HREF_GPIO_NUM;

  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;

  config.pin_pwdn  = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;

  // Reduced from 10 MHz to reduce FB-OVF
  config.xclk_freq_hz = 8000000;

  config.pixel_format = PIXFORMAT_JPEG;

  // SafeHer app: the detector resizes to 640x640, so QVGA is upscaled and its
  // detail is gone before the model sees it — knives suffer most, being the
  // thinner and already weaker class. VGA is the better match.
  //
  // If FB-OVF errors return on the serial monitor, this is the first thing to
  // put back to FRAMESIZE_QVGA; a stable QVGA stream beats a stuttering VGA one.
  config.frame_size = FRAMESIZE_VGA;

  // Lower number = better quality on this driver. 20 was chosen for a smaller
  // frame at QVGA; 12 at VGA keeps frames near 30-60 kB, which is what
  // sustains a usable rate over 2.4 GHz WiFi.
  config.jpeg_quality = 12;

  // SafeHer app: two buffers so capture and transmit overlap. With one, the
  // sensor stalls waiting for the previous frame to finish sending and the
  // frame rate roughly halves. Needs PSRAM, which the Sense variant has.
  config.fb_count = 2;

  config.grab_mode = CAMERA_GRAB_LATEST;
  config.fb_location = CAMERA_FB_IN_PSRAM;

  if (!psramFound()) {
    // Say so loudly: without PSRAM this runs badly rather than failing, and
    // the symptom is a stuttering stream that looks like a network problem.
    Serial.println("WARNING: no PSRAM — check Tools > PSRAM = OPI PSRAM");
    config.fb_count = 1;
    config.frame_size = FRAMESIZE_QVGA;
    config.fb_location = CAMERA_FB_IN_DRAM;
  }

  esp_err_t err = esp_camera_init(&config);

  if (err != ESP_OK) {
    Serial.print("Camera initialization failed: 0x");
    Serial.println(err, HEX);
    while (true) {
      delay(1000);
    }
  }

  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    s->set_vflip(s, 1);       // the glasses mount the sensor upside down
    s->set_brightness(s, 1);  // outdoors at dusk is the case that matters
  }

  Serial.println("Camera initialized successfully.");
}

// =====================================================
// MICROPHONE INITIALIZATION
// =====================================================

void startMicrophone() {

  i2s_chan_config_t chan_cfg =
      I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_AUTO, I2S_ROLE_MASTER);

  chan_cfg.dma_desc_num = 16;
  chan_cfg.dma_frame_num = 1024;

  ESP_ERROR_CHECK(i2s_new_channel(&chan_cfg, NULL, &rx_handle));

  i2s_pdm_rx_config_t pdm_cfg = {
    .clk_cfg  = I2S_PDM_RX_CLK_DEFAULT_CONFIG(SAMPLE_RATE),
    .slot_cfg = I2S_PDM_RX_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT,
                                               I2S_SLOT_MODE_MONO),
    .gpio_cfg = {
      .clk = (gpio_num_t)I2S_CLK,
      .din = (gpio_num_t)I2S_DATA,
      .invert_flags = { .clk_inv = false }
    }
  };

  ESP_ERROR_CHECK(i2s_channel_init_pdm_rx_mode(rx_handle, &pdm_cfg));
  ESP_ERROR_CHECK(i2s_channel_enable(rx_handle));

  Serial.println("Microphone initialized successfully.");
  Serial.println("Audio: 16 kHz / 16-bit / Mono");
}

// =====================================================
// WIFI CONNECTION
// =====================================================

void connectWiFi() {

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting to Wi-Fi");

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (++attempts >= 60) {
      Serial.println();
      Serial.println("Wi-Fi connection failed.");
      ESP.restart();
    }
  }

  Serial.println();
  Serial.print("ESP32 IP Address: ");
  Serial.println(WiFi.localIP());

  // SafeHer app: without this the app can reach the glasses only by raw IP,
  // which its release build refuses.
  if (MDNS.begin(MDNS_HOSTNAME)) {
    MDNS.addService("http", "tcp", 80);
    Serial.printf("mDNS: http://%s.local/\n", MDNS_HOSTNAME);
  } else {
    Serial.println("WARNING: mDNS failed — release builds will not connect");
  }
}

// =====================================================
// SafeHer app: STATUS — pairing depends on this
// =====================================================
//
// The app calls GET /status and refuses to save the address unless the reply
// says device = "safeher-glasses". Without that check it would pair against a
// router's admin page and then show a camera it does not have.
//
// Battery is deliberately omitted rather than sent as 0: the app reads an
// implausible zero as "no sensor", so a fabricated zero and a flat battery
// would look identical.

void sendStatus(WiFiClient &client) {

  String body = String("{\"device\":\"safeher-glasses\",\"firmware\":\"")
              + FIRMWARE_VERSION
              + "\",\"video\":true,\"audio\":true}";

  client.println("HTTP/1.1 200 OK");
  client.println("Content-Type: application/json");
  client.println("Access-Control-Allow-Origin: *");
  client.print  ("Content-Length: ");
  client.println(body.length());
  client.println("Connection: close");
  client.println();
  client.print(body);
  client.flush();
}

// =====================================================
// SafeHer app: AUDIO over HTTP as streaming WAV
// =====================================================
//
// The app's evidence recorder reads WAV over HTTP, not the WebSocket the demo
// uses, so both are served. The declared sizes are 0xFFFFFFFF because a live
// microphone has no length in advance; readers take bytes until the connection
// closes.

void sendWavHeader(WiFiClient &client) {

  const uint32_t byteRate = SAMPLE_RATE * 2;   // mono, 16-bit

  uint8_t wav[44] = {
    'R','I','F','F', 0xFF,0xFF,0xFF,0xFF, 'W','A','V','E',
    'f','m','t',' ', 16,0,0,0, 1,0, 1,0,
    (uint8_t)(SAMPLE_RATE      ), (uint8_t)(SAMPLE_RATE >>  8),
    (uint8_t)(SAMPLE_RATE >> 16), (uint8_t)(SAMPLE_RATE >> 24),
    (uint8_t)(byteRate      ), (uint8_t)(byteRate >>  8),
    (uint8_t)(byteRate >> 16), (uint8_t)(byteRate >> 24),
    2,0, 16,0,
    'd','a','t','a', 0xFF,0xFF,0xFF,0xFF,
  };

  client.println("HTTP/1.1 200 OK");
  client.println("Content-Type: audio/wav");
  client.println("Access-Control-Allow-Origin: *");
  client.println("Connection: close");
  client.println();
  client.write(wav, sizeof(wav));
}

// =====================================================
// SafeHer app: read the request line so routes can differ
// =====================================================
//
// This is the change that makes pairing possible at all. The demo sent MJPEG
// headers to every client that connected, whatever it asked for — so GET
// /status returned a video stream, the app could not parse it as JSON, and
// pairing failed with no useful message.

String readRequestPath(WiFiClient &client) {

  unsigned long deadline = millis() + 1000;

  while (!client.available()) {
    if (millis() > deadline) return "";
    delay(1);
  }

  String line = client.readStringUntil('\n');   // e.g. "GET /status HTTP/1.1"

  int first = line.indexOf(' ');
  if (first < 0) return "";

  int second = line.indexOf(' ', first + 1);
  if (second < 0) return "";

  // Drain the remaining headers so the socket is clean.
  while (client.available()) {
    String header = client.readStringUntil('\n');
    if (header.length() <= 1) break;
  }

  return line.substring(first + 1, second);
}

// =====================================================
// VIDEO STREAM TASK
// =====================================================

void videoStreamTask(void *parameter) {

  Serial.println("Video streaming task started.");

  while (true) {

    if (videoClient && !videoClient.connected()) {
      videoClient.stop();
      Serial.println("Video client disconnected.");
    }

    // =================================================
    // Accept and route
    // =================================================

    WiFiClient newClient = videoServer.available();

    if (newClient) {

      newClient.setNoDelay(true);
      newClient.setTimeout(1000);

      String path = readRequestPath(newClient);

      if (path == "/status") {

        // Answered and closed immediately, so pairing never has to wait for
        // the video slot to free up.
        sendStatus(newClient);
        newClient.stop();

      } else if (path == "/audio") {

        if (audioHttpClient) audioHttpClient.stop();
        audioHttpClient = newClient;
        sendWavHeader(audioHttpClient);
        Serial.println("Audio client connected (HTTP).");

      } else {

        // "/stream", "/" or anything else — the app asks for /stream.
        if (videoClient) videoClient.stop();
        videoClient = newClient;

        Serial.println("Video client connected.");

        videoClient.println("HTTP/1.1 200 OK");
        videoClient.println(
            "Content-Type: multipart/x-mixed-replace; boundary=frame");
        videoClient.println("Cache-Control: no-cache, no-store, must-revalidate");
        videoClient.println("Access-Control-Allow-Origin: *");
        videoClient.println();

        delay(50);
      }
    }

    // =================================================
    // CAPTURE + SEND VIDEO
    // =================================================

    if (videoClient && videoClient.connected()) {

      camera_fb_t *fb = esp_camera_fb_get();

      if (fb == NULL) {
        Serial.println("Camera capture failed.");
        delay(50);
        continue;
      }

      size_t frameLength = fb->len;

      // The phone's parser reads Content-Length and consumes exactly that many
      // bytes, so a part without one is skipped and a wrong one desynchronises
      // the whole stream rather than costing a single frame.
      videoClient.print("--frame\r\n");
      videoClient.print("Content-Type: image/jpeg\r\n");
      videoClient.print("Content-Length: ");
      videoClient.print(frameLength);
      videoClient.print("\r\n\r\n");

      size_t written = videoClient.write(fb->buf, frameLength);

      esp_camera_fb_return(fb);

      videoClient.print("\r\n");

      if (written != frameLength) {
        Serial.println("Incomplete video transmission.");
        videoClient.stop();
      }

      // SafeHer app: the phone infers at about 5 fps and votes over a window
      // of frames, so ~10 fps here is ample. The old 150 ms gave 6-7 fps at
      // QVGA; 100 ms at VGA is a better match without saturating the link.
      delay(100);

    } else {
      delay(10);
    }
  }
}

// =====================================================
// AUDIO WEBSOCKET EVENTS
// =====================================================

void audioWebSocketEvent(uint8_t clientNumber, WStype_t type,
                         uint8_t *payload, size_t length) {

  switch (type) {
    case WStype_CONNECTED:
      Serial.printf("Audio client connected (ws): %u\n", clientNumber);
      break;
    case WStype_DISCONNECTED:
      Serial.printf("Audio client disconnected (ws): %u\n", clientNumber);
      break;
    default:
      break;
  }
}

// =====================================================
// CONTINUOUS AUDIO STREAM
// =====================================================

void streamAudio() {

  size_t bytesRead = 0;

  esp_err_t result = i2s_channel_read(rx_handle, audioBuffer,
                                      sizeof(audioBuffer), &bytesRead, 200);

  if (result != ESP_OK || bytesRead == 0) {
    return;
  }

  int samples = bytesRead / sizeof(int16_t);

  static float dcEstimate = 0.0f;
  static float filteredSample = 0.0f;

  for (int i = 0; i < samples; i++) {

    float sample = (float)audioBuffer[i];

    // Remove DC
    dcEstimate = 0.995f * dcEstimate + 0.005f * sample;
    sample -= dcEstimate;

    // Voice gain
    sample *= 12.0f;

    // Low-pass filter
    filteredSample = 0.85f * filteredSample + 0.15f * sample;

    if (filteredSample >  30000.0f) filteredSample =  30000.0f;
    if (filteredSample < -30000.0f) filteredSample = -30000.0f;

    audioBuffer[i] = (int16_t)filteredSample;
  }

  // WebSocket — the standalone demo.
  if (audioServer.connectedClients() > 0) {
    audioServer.broadcastBIN((uint8_t*)audioBuffer, bytesRead);
  }

  // SafeHer app: the same samples over HTTP, for the evidence recorder.
  if (audioHttpClient) {
    if (audioHttpClient.connected()) {
      audioHttpClient.write((uint8_t*)audioBuffer, bytesRead);
    } else {
      audioHttpClient.stop();
      Serial.println("Audio client disconnected (HTTP).");
    }
  }
}

// =====================================================
// SETUP
// =====================================================

void setup() {

  Serial.begin(115200);
  delay(2000);

  Serial.println();
  Serial.println("========================================");
  Serial.println("       SAFEHER LIVE STREAMING");
  Serial.println("       XIAO ESP32-S3 SENSE");
  Serial.println("========================================");

  startCamera();
  startMicrophone();
  connectWiFi();

  videoServer.begin();
  Serial.println("HTTP server started on port 80.");

  audioServer.begin();
  audioServer.onEvent(audioWebSocketEvent);
  Serial.println("Audio WebSocket started on port 81.");

  xTaskCreatePinnedToCore(videoStreamTask, "VideoStream", 8192, NULL, 1, NULL, 0);

  Serial.println();
  Serial.println("========================================");
  Serial.println("          STREAMING IS READY");
  Serial.println("========================================");
  Serial.printf("video : http://%s/stream\n", WiFi.localIP().toString().c_str());
  Serial.printf("status: http://%s/status\n", WiFi.localIP().toString().c_str());
  Serial.printf("audio : http://%s/audio\n",  WiFi.localIP().toString().c_str());
  Serial.printf("pair with: %s.local\n", MDNS_HOSTNAME);
  Serial.println("========================================");
}

// =====================================================
// LOOP
// =====================================================

void loop() {

  audioServer.loop();
  streamAudio();

  // SafeHer app: reconnect rather than sit silently offline. Nobody is going
  // to power cycle a pair of glasses mid-journey.
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost — reconnecting");
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    delay(2000);
  }

  delay(1);
}
