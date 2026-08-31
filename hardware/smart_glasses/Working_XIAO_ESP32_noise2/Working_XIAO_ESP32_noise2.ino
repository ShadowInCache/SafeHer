#include <Arduino.h>
#include "esp_camera.h"
#include <SD.h>
#include <SPI.h>
#include <driver/i2s_pdm.h>
#include <math.h>
#include <WiFi.h>
#include <ESP_Mail_Client.h>
#include "thingProperties.h"

// ================= EMAIL SETTINGS =================
#define SMTP_HOST "smtp.gmail.com"
#define SMTP_PORT 465
#define AUTHOR_EMAIL "safeher49@gmail.com"
#define AUTHOR_PASSWORD "pwlwnxlpwhdxngoj"
#define RECIPIENT_EMAIL "safeher49@gmail.com"

SMTPSession smtp;

// ================= CAMERA PINS (XIAO ESP32S3) =================
#define PWDN_GPIO_NUM    -1
#define RESET_GPIO_NUM   -1
#define XCLK_GPIO_NUM    10
#define SIOD_GPIO_NUM    40
#define SIOC_GPIO_NUM    39
#define Y9_GPIO_NUM      48
#define Y8_GPIO_NUM      11
#define Y7_GPIO_NUM      12
#define Y6_GPIO_NUM      14
#define Y5_GPIO_NUM      16
#define Y4_GPIO_NUM      18
#define Y3_GPIO_NUM      17
#define Y2_GPIO_NUM      15
#define VSYNC_GPIO_NUM   38
#define HREF_GPIO_NUM    47
#define PCLK_GPIO_NUM    13

// ================= MIC SETTINGS =================
#define I2S_CLK          42   
#define I2S_DATA         41   
const float SOUND_THRESHOLD = 700.0;
#define AUDIO_GAIN       8

// ================= GLOBALS =================
const uint16_t RECORD_DURATION_SEC = 13;
i2s_chan_handle_t rx_handle = NULL;
File audioFile;
volatile bool recordingAudio = false;
uint32_t pcmBytesWritten = 0;
TaskHandle_t audioTaskHandle = NULL;

char audPath[64];
char currentFolderPath[32];
String gpsData = "";
uint32_t totalFramesCaptured = 0; 

// ================= INIT FUNCTIONS =================
void startCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM; config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM; config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM; config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM; config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM; config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM; config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM; config.pin_sccb_scl= SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM; config.pin_reset = RESET_GPIO_NUM;
  
  config.xclk_freq_hz = 10000000; 
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size   = FRAMESIZE_VGA; 
  config.jpeg_quality = 12;            
  config.fb_count     = 2;
  config.grab_mode    = CAMERA_GRAB_LATEST; 

  if (esp_camera_init(&config) != ESP_OK) {
    Serial.println("Camera init failed");
    while (1);
  }
}

void initMic() {
    i2s_chan_config_t chan_cfg = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_AUTO, I2S_ROLE_MASTER);
    chan_cfg.dma_desc_num = 16;
    chan_cfg.dma_frame_num = 1024;
    ESP_ERROR_CHECK(i2s_new_channel(&chan_cfg, NULL, &rx_handle));

    i2s_pdm_rx_config_t pdm_cfg = {
        .clk_cfg = I2S_PDM_RX_CLK_DEFAULT_CONFIG(16000),
        .slot_cfg = I2S_PDM_RX_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = { .clk = (gpio_num_t)I2S_CLK, .din = (gpio_num_t)I2S_DATA, .invert_flags = { .clk_inv = false } },
    };
    ESP_ERROR_CHECK(i2s_channel_init_pdm_rx_mode(rx_handle, &pdm_cfg));
    ESP_ERROR_CHECK(i2s_channel_enable(rx_handle));
}

// ================= MIC RMS TRIGGER =================
float getSoundLevel() {
    int16_t triggerSamples[128];
    float peakRMS = 0;

    for (int w = 0; w < 8; w++) {
        size_t bytesRead = 0;
        if (i2s_channel_read(rx_handle, triggerSamples, sizeof(triggerSamples), &bytesRead, 100) != ESP_OK) continue;
        
        int count = bytesRead / sizeof(int16_t);
        if (count == 0) continue;

        long mean = 0;
        for (int i = 0; i < count; i++) mean += triggerSamples[i];
        mean /= count;

        double sum = 0;
        for (int i = 0; i < count; i++) {
            float s = triggerSamples[i] - mean;
            sum += s * s;
        }

        float rms = sqrt(sum / count);
        if (rms > peakRMS) peakRMS = rms;
    }
    return peakRMS;
}

void flushAudioBuffer() {
  int16_t dummy[512];
  size_t bytesRead = 0;
  while (i2s_channel_read(rx_handle, dummy, sizeof(dummy), &bytesRead, 0) == ESP_OK && bytesRead > 0) {}
}

// ================= RECORDING TASK (CORE 0 & 1) =================
void audioTask(void *parameter) {
  int16_t audioBuffer[512];
  size_t bytesRead = 0;

  while (recordingAudio) {
    if (i2s_channel_read(rx_handle, audioBuffer, sizeof(audioBuffer), &bytesRead, 20) == ESP_OK) {
      if (bytesRead > 0) {
        int numSamples = bytesRead / 2; 
        for (int i = 0; i < numSamples; i++) {
          int32_t amplified = (int32_t)audioBuffer[i] * AUDIO_GAIN;
          if (amplified > 32767) amplified = 32767;
          if (amplified < -32768) amplified = -32768;
          audioBuffer[i] = (int16_t)amplified;
        }
        audioFile.write((uint8_t *)audioBuffer, bytesRead);
        pcmBytesWritten += bytesRead;
      }
    }
    taskYIELD(); 
  }
  audioTaskHandle = NULL;
  vTaskDelete(NULL);
}

void recordEvent() {
  int folderIndex = 1;
  do {
    snprintf(currentFolderPath, sizeof(currentFolderPath), "/EVENT%04d", folderIndex);
    folderIndex++;
  } while (SD.exists(currentFolderPath));
  SD.mkdir(currentFolderPath);
  
  snprintf(audPath, sizeof(audPath), "%s/audio.wav", currentFolderPath);
  audioFile = SD.open(audPath, FILE_WRITE);
  
  uint8_t header[44] = { 'R','I','F','F', 0,0,0,0, 'W','A','V','E', 'f','m','t',' ', 16,0,0,0, 1,0, 1,0, 0x80,0x3E,0x00,0x00, 0x00,0x7D,0x00,0x00, 2,0, 16,0, 'd','a','t','a', 0,0,0,0 };
  audioFile.write(header, 44);
  pcmBytesWritten = 0;
  totalFramesCaptured = 0;

  recordingAudio = true;
  xTaskCreatePinnedToCore(audioTask, "AudioTask", 4096, NULL, 2, &audioTaskHandle, 0);

  Serial.printf("Recording 13s event to %s...\n", currentFolderPath);
  uint32_t startMs = millis();
  uint32_t nextFrameMs = startMs;
  
  while (millis() - startMs < (RECORD_DURATION_SEC * 1000UL)) {
    if (millis() >= nextFrameMs) {
      nextFrameMs += 100; 
      camera_fb_t *fb = esp_camera_fb_get();
      if (fb != NULL) {
        totalFramesCaptured++;
        char imgPath[64];
        snprintf(imgPath, sizeof(imgPath), "%s/frame%05d.jpg", currentFolderPath, totalFramesCaptured);
        
        File imgFile = SD.open(imgPath, FILE_WRITE);
        if (imgFile) {
          imgFile.write(fb->buf, fb->len);
          imgFile.close();
        } 
        esp_camera_fb_return(fb);
      }
    }
  }

  recordingAudio = false;
  while (audioTaskHandle != NULL) { delay(10); }

  uint32_t riffSize = pcmBytesWritten + 36;
  audioFile.seek(4);  audioFile.write((uint8_t *)&riffSize, 4);
  audioFile.seek(40); audioFile.write((uint8_t *)&pcmBytesWritten, 4);
  audioFile.close();
  
  Serial.printf("Event safely saved to SD. Total Frames: %d\n", totalFramesCaptured);
}

// ================= EMAIL & CLOUD =================
void sendEmail(String gpsData) {
  SMTP_Message message;
  message.sender.name = "ESP32 Security Alert";
  message.sender.email = AUTHOR_EMAIL;
  message.subject = "⚠ Noise Alert Detected!";
  message.addRecipient("User", RECIPIENT_EMAIL);

  String emailText = "Noise threshold exceeded.\n\n";
  emailText += "GPS Coordinates:\n";
  emailText += gpsData;
  emailText += "\n\nAttached: Audio recording and Start/Mid/End event frames.";
  message.text.content = emailText.c_str();

  SMTP_Attachment attAudio;
  attAudio.descr.filename = "audio.wav";
  attAudio.descr.mime = "audio/wav";
  attAudio.file.path = audPath;
  attAudio.file.storage_type = esp_mail_file_storage_type_sd;
  message.addAttachment(attAudio);

  if (totalFramesCaptured > 0) {
    uint32_t midFrame = totalFramesCaptured / 2;
    if (midFrame == 0) midFrame = 1;

    char pathStart[64], pathMid[64], pathEnd[64];
    snprintf(pathStart, sizeof(pathStart), "%s/frame%05d.jpg", currentFolderPath, 1);
    snprintf(pathMid, sizeof(pathMid), "%s/frame%05d.jpg", currentFolderPath, midFrame);
    snprintf(pathEnd, sizeof(pathEnd), "%s/frame%05d.jpg", currentFolderPath, totalFramesCaptured);

    SMTP_Attachment attStart;
    attStart.descr.filename = "1_start.jpg";  attStart.descr.mime = "image/jpeg";
    attStart.file.path = pathStart;           attStart.file.storage_type = esp_mail_file_storage_type_sd;
    message.addAttachment(attStart);

    if (totalFramesCaptured >= 2) {
      SMTP_Attachment attMid;
      attMid.descr.filename = "2_mid.jpg";    attMid.descr.mime = "image/jpeg";
      attMid.file.path = pathMid;             attMid.file.storage_type = esp_mail_file_storage_type_sd;
      message.addAttachment(attMid);
    }
    if (totalFramesCaptured >= 3) {
      SMTP_Attachment attEnd;
      attEnd.descr.filename = "3_end.jpg";    attEnd.descr.mime = "image/jpeg";
      attEnd.file.path = pathEnd;             attEnd.file.storage_type = esp_mail_file_storage_type_sd;
      message.addAttachment(attEnd);
    }
  }

  ESP_Mail_Session session;
  session.server.host_name = SMTP_HOST;
  session.server.port = SMTP_PORT;
  session.login.email = AUTHOR_EMAIL;
  session.login.password = AUTHOR_PASSWORD;

  if (!smtp.connect(&session)) { Serial.println("SMTP connection failed"); return; }
  if (!MailClient.sendMail(&smtp, &message)) { Serial.println("Email send failed"); } 
  else { Serial.println("Email sent successfully!"); }
  smtp.closeSession();
}

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("Starting System...");

  startCamera();
  if (!SD.begin(21)) { Serial.println("SD Init Failed"); while(1); }
  initMic();
  
  // 1. Initialize Cloud variables ONLY ONCE here.
  initProperties();
  ArduinoCloud.begin(ArduinoIoTPreferredConnection);
  setDebugMessageLevel(2);

  // 2. Disconnect WiFi so we can listen in peace
  WiFi.disconnect(true);
  WiFi.mode(WIFI_OFF);
  
  Serial.println("System Ready! Listening for sound...");
}

// ================= MAIN LOOP =================
void loop() {
  float value = getSoundLevel();

  if (value > SOUND_THRESHOLD) {
    Serial.println("================================");
    Serial.println("NOISE DETECTED");
    
    // Debounce check
    delay(100);
    value = getSoundLevel();
    
    if (value > SOUND_THRESHOLD) {
      Serial.println("Noise Confirmed!");

      // 1. Capture Event to SD
      recordEvent();

      // 2. PAUSE SENSORS (Critical fix for Memory & Email failures)
      Serial.println("Powering down Camera and Mic to free RAM...");
      esp_camera_deinit();
      i2s_channel_disable(rx_handle);
      delay(500); // Give hardware a moment to settle

      // 3. Connect WiFi & IoT Cloud
      Serial.println("Connecting WiFi...");
      WiFi.mode(WIFI_STA);
      WiFi.begin(SSID, PASS); // Uses credentials from thingProperties
      while(WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
      
      Serial.println("\nWiFi Connected. Waiting for Arduino Cloud Sync...");
      unsigned long cloudWait = millis();
      
      // Increased to 15 seconds to allow the TLS security handshake to finish
      while (millis() - cloudWait < 15000) {
        ArduinoCloud.update();
        if (ArduinoCloud.connected()) {
          Serial.println("Cloud Connected! Syncing variables...");
          delay(1000); // Give the cloud 1 second to download Loc1 state
          break;
        }
        delay(100);
      }

      // 4. Fetch GPS (4-Second Window)
      Serial.println("Fetching GPS Coordinates...");
      unsigned long gpsWait = millis();
      gpsData = "";

      while (millis() - gpsWait < 4000) {
        ArduinoCloud.update();
        Location loc = Loc1.getValue();
        
        if (loc.lat != 0 && loc.lon != 0) {
          Serial.println("Valid GPS received from Cloud!");
          gpsData += "Latitude: " + String(loc.lat, 6) + "\nLongitude: " + String(loc.lon, 6);
          gpsData += "\n\nGoogle Maps Link:\n";
          gpsData += "https://www.google.com/maps/search/?api=1&query=" + String(loc.lat, 6) + "," + String(loc.lon, 6);
          delay(500);
          break;
        }
        delay(500); 
      }

      

      // 5. Send Email
      Serial.println("Sending Security Email...");
      sendEmail(gpsData);

      // 6. Cleanup & Disconnect
      Serial.println("Disconnecting WiFi...");
      WiFi.disconnect(true);
      WiFi.mode(WIFI_OFF);
      delay(2000);

      // 7. WAKE SENSORS BACK UP
      Serial.println("Waking up Camera and Mic...");
      startCamera();
      i2s_channel_enable(rx_handle);
      
      Serial.println("Cooldown before listening again...");
      delay(5000);
      flushAudioBuffer();
      Serial.println("Listening for sound...");
    }
  }

  // Silently discard unused camera frames to prevent FB-OVF spam
  camera_fb_t *fb = esp_camera_fb_get();
  if (fb != NULL) {
    esp_camera_fb_return(fb);
  }

  delay(20);
}

// ================= CLOUD CALLBACKS =================
void handleLocation(float lat, float lon) {}
void onV0Change() {}
void onStr1Change() {}
void onLoc1Change() {}