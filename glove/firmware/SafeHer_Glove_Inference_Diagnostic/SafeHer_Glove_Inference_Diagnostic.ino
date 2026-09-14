// ============================================================================
// SafeHer Glove - Real-Time Inference Diagnostic (NEW, separate from production)
//
// STATUS: Written but NOT compiled or flashed in this environment - no
// ESP32-C3/MPU-6500 hardware was available when this file was created. Not
// built with arduino-cli/PlatformIO, not run on a device. Compile and flash
// it yourself, then report back the printed measurements.
//
// This is SafeHer_Glove_Final.ino's architecture (two FreeRTOS tasks:
// high-priority sampling, low-priority inference/output; same MPU-6500
// setup; same DATA_COLLECTION_MODE gate) with per-inference timing
// instrumentation added on top:
//   - feature extraction time (us)
//   - forest evaluation (XGBoost) time (us)
//   - total inference time (us)
//   - time between successive inference outputs (ms)
// and it reuses the SAME sampling-timing diagnostic counters as production
// (avg/min/max interval, late-sample counts) so you can see directly
// whether a slow inference cycle ever coincides with a sampling gap.
//
// UNCHANGED from production: WINDOW_SIZE=100, OVERLAP=50 (=> STEP=50),
// SAMPLE_INTERVAL_US=10000 (100 Hz), FEATURE_COUNT=51, the 51-feature
// formulas/order, NUM_CLASSES=7 and class order, FALL_CONFIDENCE_THRESHOLD
// =0.65, the 2-hit FALL debounce, and the embedded model files
// (safeher_glove_final_model.h/.cpp, copied byte-for-byte into this folder
// so this sketch can compile standalone -- verified identical by SHA-256
// to firmware/SafeHer_Glove_Final/'s copies before writing this file).
//
// IMPORTANT: like production, this sketch's inference/BLE path only runs
// when DATA_COLLECTION_MODE is 0 below. It defaults to 0 here (diagnostic
// mode is the point of this file), unlike the current production .ino
// which is presently set to 1 (data-collection/raw-CSV mode) -- see the
// hardware validation report for that finding.
//
// Does not modify SafeHer_Glove_Final.ino, its model files, or any other
// existing file.
// ============================================================================

#include <Wire.h>
#include <math.h>
#include <string.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
#include "safeher_glove_final_model.h"

#define MPU_ADDR 0x68
#define WHO_AM_I_REG 0x75
#define PWR_MGMT_1 0x6B
#define ACCEL_CONFIG 0x1C
#define GYRO_CONFIG 0x1B
#define ACCEL_XOUT_H 0x3B

#define SAMPLE_INTERVAL_US 10000UL
#define WINDOW_SIZE 100
#define OVERLAP 50
#define NUM_CLASSES 7
#define FEATURE_COUNT 51
#define FALL_CONFIDENCE_THRESHOLD 0.65f
#define DATA_COLLECTION_MODE 0   // diagnostic mode always runs inference

#define BLE_DEVICE_NAME "SafeHer-Glove-Diag"
#define BLE_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

#define SAMPLING_TASK_PRIORITY 3
#define INFERENCE_TASK_PRIORITY 1
#define SAMPLING_TASK_STACK_BYTES 3072
#define INFERENCE_TASK_STACK_BYTES 8192

#define REPORT_INTERVAL_SAMPLES 500UL
#define CLOSE_TOLERANCE_US 1000UL
#define LATE_THRESHOLD_US 12000UL

const char* const CLASS_NAMES[NUM_CLASSES] = {
  "NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"
};

struct FeatureStats { float mean, std, minv, maxv, range, rms; };

float axWindow[WINDOW_SIZE], ayWindow[WINDOW_SIZE], azWindow[WINDOW_SIZE];
float gxWindow[WINDOW_SIZE], gyWindow[WINDOW_SIZE], gzWindow[WINDOW_SIZE];
int windowCount = 0;

struct SensorWindow {
  float ax[WINDOW_SIZE], ay[WINDOW_SIZE], az[WINDOW_SIZE];
  float gx[WINDOW_SIZE], gy[WINDOW_SIZE], gz[WINDOW_SIZE];
};

static SensorWindow snapshotBuffer[2];
static volatile bool snapshotConsumed[2] = {true, true};
static QueueHandle_t windowQueue = nullptr;

uint32_t windowNumber = 0;
int fallConfirmationCount = 0;

struct SamplingStats {
  uint32_t sampleCount, minDtUs, maxDtUs, closeCount, lateCount;
  uint64_t sumDtUs;
};
static volatile SamplingStats gStats = {0, 0xFFFFFFFFUL, 0, 0, 0, 0};
static volatile bool gDiagnosticsReady = false;
static SamplingStats gReportSnapshot;

// Set by inferenceTask right before/after the slow work, read by the
// sampling task's diagnostics purely to correlate: "was an inference
// in-flight when this sample's dt was measured?" (single bool, no lock
// needed on this single-core target for a plain read/write of one word).
static volatile bool gInferenceInFlight = false;
static volatile uint32_t gLateSamplesDuringInference = 0;

BLECharacteristic* bleResultCharacteristic = nullptr;
volatile bool blePhoneConnected = false;

class DiagBleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    blePhoneConnected = true;
    Serial.println("BLE: Phone connected");
  }
  void onDisconnect(BLEServer* server) override {
    blePhoneConnected = false;
    Serial.println("BLE: Phone disconnected");
    BLEDevice::startAdvertising();
  }
};

void initializeBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEServer* bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new DiagBleServerCallbacks());
  BLEService* bleService = bleServer->createService(BLE_SERVICE_UUID);
  bleResultCharacteristic = bleService->createCharacteristic(
      BLE_CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  bleResultCharacteristic->addDescriptor(new BLE2902());
  bleResultCharacteristic->setValue("NORMAL,0.00");
  bleService->start();
  BLEAdvertising* bleAdvertising = BLEDevice::getAdvertising();
  bleAdvertising->addServiceUUID(BLE_SERVICE_UUID);
  bleAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("BLE: Advertising started");
}

void notifyClassification(int predictedClass, float confidence) {
  if (!blePhoneConnected || bleResultCharacteristic == nullptr) return;
  char message[32];
  snprintf(message, sizeof(message), "%s,%.2f", CLASS_NAMES[predictedClass], confidence);
  bleResultCharacteristic->setValue(message);
  bleResultCharacteristic->notify();
}

void writeRegister(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(value);
  Wire.endTransmission();
}

uint8_t readRegister(uint8_t reg) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 1);
  if (Wire.available()) return Wire.read();
  return 0xFF;
}

void readSensorRaw(int16_t& axRaw, int16_t& ayRaw, int16_t& azRaw,
                    int16_t& gxRaw, int16_t& gyRaw, int16_t& gzRaw) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(ACCEL_XOUT_H);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 14);
  if (Wire.available() < 14) {
    axRaw = ayRaw = azRaw = gxRaw = gyRaw = gzRaw = 0;
    return;
  }
  axRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  ayRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  azRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  Wire.read(); Wire.read();
  gxRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  gyRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  gzRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
}

// Byte-for-byte the same formulas/order as production - not re-derived, not
// modified, just copied so this file compiles standalone.
void computeStats(const float* values, int len, FeatureStats& stats) {
  if (len <= 0) { stats = {0,0,0,0,0,0}; return; }
  float sum = 0, sumSquares = 0, minv = values[0], maxv = values[0];
  for (int i = 0; i < len; ++i) {
    const float v = values[i];
    sum += v; sumSquares += v * v;
    if (v < minv) minv = v;
    if (v > maxv) maxv = v;
  }
  const float mean = sum / (float)len;
  float variance = 0;
  for (int i = 0; i < len; ++i) { const float d = values[i] - mean; variance += d * d; }
  variance /= (float)len;
  stats.mean = mean; stats.std = sqrtf(variance);
  stats.minv = minv; stats.maxv = maxv;
  stats.range = maxv - minv; stats.rms = sqrtf(sumSquares / (float)len);
}

void addStats(float* features, int& featureIndex, const float* values, int len) {
  FeatureStats stats;
  computeStats(values, len, stats);
  features[featureIndex++] = stats.mean;
  features[featureIndex++] = stats.std;
  features[featureIndex++] = stats.minv;
  features[featureIndex++] = stats.maxv;
  features[featureIndex++] = stats.range;
  features[featureIndex++] = stats.rms;
}

void extractWindowFeatures(const SensorWindow& window, float* features) {
  int idx = 0;
  addStats(features, idx, window.ax, WINDOW_SIZE);
  addStats(features, idx, window.ay, WINDOW_SIZE);
  addStats(features, idx, window.az, WINDOW_SIZE);
  addStats(features, idx, window.gx, WINDOW_SIZE);
  addStats(features, idx, window.gy, WINDOW_SIZE);
  addStats(features, idx, window.gz, WINDOW_SIZE);

  float accMag[WINDOW_SIZE], gyroMag[WINDOW_SIZE];
  for (int i = 0; i < WINDOW_SIZE; ++i) {
    accMag[i] = sqrtf(window.ax[i]*window.ax[i] + window.ay[i]*window.ay[i] + window.az[i]*window.az[i]);
    gyroMag[i] = sqrtf(window.gx[i]*window.gx[i] + window.gy[i]*window.gy[i] + window.gz[i]*window.gz[i]);
  }
  addStats(features, idx, accMag, WINDOW_SIZE);
  addStats(features, idx, gyroMag, WINDOW_SIZE);

  float jerk[WINDOW_SIZE - 1];
  for (int i = 0; i < WINDOW_SIZE - 1; ++i) jerk[i] = accMag[i+1] - accMag[i];
  FeatureStats jerkStats;
  computeStats(jerk, WINDOW_SIZE - 1, jerkStats);
  features[idx++] = jerkStats.mean;
  features[idx++] = jerkStats.std;
  features[idx++] = jerkStats.maxv;

  while (idx < FEATURE_COUNT) features[idx++] = 0.0f;
}

const char* applyFallConfirmation(int predictedClass, float confidence) {
  if (predictedClass != 6) {
    fallConfirmationCount = 0;
    return (predictedClass == 0) ? "SAFE" : "ABNORMAL";
  }
  if (confidence >= FALL_CONFIDENCE_THRESHOLD) fallConfirmationCount++;
  else fallConfirmationCount = 0;
  return (fallConfirmationCount >= 2) ? "HIGH_RISK" : "ABNORMAL";
}

void printSamplingDiagnostics(const SamplingStats& stats) {
  const uint32_t avgDtUs = (stats.sampleCount > 0) ? (uint32_t)(stats.sumDtUs / stats.sampleCount) : 0;
  Serial.println("SAMPLING:");
  Serial.printf("samples=%u avg_dt_us=%u min_dt_us=%u max_dt_us=%u close=%u late=%u\n",
               stats.sampleCount, avgDtUs, stats.minDtUs, stats.maxDtUs, stats.closeCount, stats.lateCount);
  Serial.printf("late_samples_during_inference=%u\n", gLateSamplesDuringInference);
}

// ----------------------------------------------------------------------------
// Inference task - identical algorithm to production, with timing added
// around feature extraction and forest evaluation specifically, plus a
// window counter and inter-inference-interval measurement.
// ----------------------------------------------------------------------------
void inferenceTask(void* pvParameters) {
  static float features[FEATURE_COUNT];
  static float scores[NUM_CLASSES];
  unsigned long lastInferenceEndMs = millis();

  for (;;) {
    uint8_t slot;
    if (xQueueReceive(windowQueue, &slot, portMAX_DELAY) != pdTRUE) continue;

    static SensorWindow localWindow;
    memcpy(&localWindow, &snapshotBuffer[slot], sizeof(SensorWindow));
    snapshotConsumed[slot] = true;

    gInferenceInFlight = true;
    const unsigned long t0 = micros();

    for (int i = 0; i < FEATURE_COUNT; ++i) features[i] = 0.0f;
    extractWindowFeatures(localWindow, features);

    const unsigned long t1 = micros();
    SafeHer::V5Embedded::evaluate_forest(features, scores);
    const unsigned long t2 = micros();

    const int predictedClass = SafeHer::V5Embedded::predict_class(scores);
    const float confidence = SafeHer::V5Embedded::predict_confidence(scores);
    const char* safetyText = applyFallConfirmation(predictedClass, confidence);
    gInferenceInFlight = false;

    const unsigned long featureUs = t1 - t0;
    const unsigned long forestUs = t2 - t1;
    const unsigned long totalUs = t2 - t0;

    const unsigned long nowMs = millis();
    const unsigned long intervalMs = nowMs - lastInferenceEndMs;
    lastInferenceEndMs = nowMs;

    windowNumber++;
    Serial.printf(
      "SAFEHER INFERENCE window=%lu class=%s confidence=%.3f safety=%s "
      "feature_us=%lu forest_us=%lu total_us=%lu interval_since_last_ms=%lu\n",
      windowNumber, CLASS_NAMES[predictedClass], confidence, safetyText,
      featureUs, forestUs, totalUs, intervalMs);

    notifyClassification(predictedClass, confidence);

    if (gDiagnosticsReady) {
      printSamplingDiagnostics(gReportSnapshot);
      gDiagnosticsReady = false;
    }
  }
}

// ----------------------------------------------------------------------------
// Sampling task - identical to production; additionally flags whether a
// late sample happened while an inference was in flight, so the report can
// state directly whether inference ever caused a sampling gap.
// ----------------------------------------------------------------------------
void samplingTask(void* pvParameters) {
  unsigned long nextSampleTime = micros();
  unsigned long lastActualSampleMicros = nextSampleTime;
  uint8_t nextSnapshotSlot = 0;
  bool haveLastSample = false;

  for (;;) {
    const unsigned long now = micros();
    const long remaining = (long)(nextSampleTime - now);
    if (remaining > 0) {
      if (remaining > 1000) vTaskDelay(1);
      continue;
    }
    nextSampleTime += SAMPLE_INTERVAL_US;

    int16_t axRaw=0, ayRaw=0, azRaw=0, gxRaw=0, gyRaw=0, gzRaw=0;
    readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);

    const unsigned long actualNow = micros();
    if (haveLastSample) {
      const uint32_t dt = (uint32_t)(actualNow - lastActualSampleMicros);
      gStats.sampleCount++;
      gStats.sumDtUs += dt;
      if (dt < gStats.minDtUs) gStats.minDtUs = dt;
      if (dt > gStats.maxDtUs) gStats.maxDtUs = dt;
      if (dt <= SAMPLE_INTERVAL_US + CLOSE_TOLERANCE_US && dt + CLOSE_TOLERANCE_US >= SAMPLE_INTERVAL_US) gStats.closeCount++;
      if (dt > LATE_THRESHOLD_US) {
        gStats.lateCount++;
        if (gInferenceInFlight) gLateSamplesDuringInference++;
      }
      if (gStats.sampleCount >= REPORT_INTERVAL_SAMPLES && !gDiagnosticsReady) {
        gReportSnapshot.sampleCount = gStats.sampleCount;
        gReportSnapshot.minDtUs = gStats.minDtUs;
        gReportSnapshot.maxDtUs = gStats.maxDtUs;
        gReportSnapshot.sumDtUs = gStats.sumDtUs;
        gReportSnapshot.closeCount = gStats.closeCount;
        gReportSnapshot.lateCount = gStats.lateCount;
        gDiagnosticsReady = true;
        gStats.sampleCount = 0; gStats.minDtUs = 0xFFFFFFFFUL; gStats.maxDtUs = 0;
        gStats.sumDtUs = 0; gStats.closeCount = 0; gStats.lateCount = 0;
      }
    }
    lastActualSampleMicros = actualNow;
    haveLastSample = true;

    if (windowCount < WINDOW_SIZE) {
      axWindow[windowCount] = (float)axRaw; ayWindow[windowCount] = (float)ayRaw; azWindow[windowCount] = (float)azRaw;
      gxWindow[windowCount] = (float)gxRaw; gyWindow[windowCount] = (float)gyRaw; gzWindow[windowCount] = (float)gzRaw;
      windowCount++;
    }

    if (windowCount == WINDOW_SIZE) {
      if (snapshotConsumed[nextSnapshotSlot]) {
        snapshotConsumed[nextSnapshotSlot] = false;
        memcpy(snapshotBuffer[nextSnapshotSlot].ax, axWindow, sizeof(axWindow));
        memcpy(snapshotBuffer[nextSnapshotSlot].ay, ayWindow, sizeof(ayWindow));
        memcpy(snapshotBuffer[nextSnapshotSlot].az, azWindow, sizeof(azWindow));
        memcpy(snapshotBuffer[nextSnapshotSlot].gx, gxWindow, sizeof(gxWindow));
        memcpy(snapshotBuffer[nextSnapshotSlot].gy, gyWindow, sizeof(gyWindow));
        memcpy(snapshotBuffer[nextSnapshotSlot].gz, gzWindow, sizeof(gzWindow));
        xQueueSend(windowQueue, &nextSnapshotSlot, 0);
        nextSnapshotSlot = 1 - nextSnapshotSlot;
      }
      for (int i = 0; i < OVERLAP; ++i) {
        axWindow[i] = axWindow[i+OVERLAP]; ayWindow[i] = ayWindow[i+OVERLAP]; azWindow[i] = azWindow[i+OVERLAP];
        gxWindow[i] = gxWindow[i+OVERLAP]; gyWindow[i] = gyWindow[i+OVERLAP]; gzWindow[i] = gzWindow[i+OVERLAP];
      }
      windowCount = WINDOW_SIZE - OVERLAP;
    }
  }
}

void initializeMPU6500() {
  writeRegister(PWR_MGMT_1, 0x00); delay(100);
  writeRegister(ACCEL_CONFIG, 0x00);
  writeRegister(GYRO_CONFIG, 0x00); delay(100);
}

void setup() {
  Serial.begin(115200);
  delay(1500);

  Serial.println("SafeHer Glove - INFERENCE DIAGNOSTIC");
  Serial.println("Same model/features/timing as production, with per-inference timing added.");
  Serial.println("Window: 100 samples, Step: 50 samples, Features: 51, Classes: 7");
  Serial.println("FALL threshold: 0.65, 2-hit debounce");

  Wire.begin();
  Wire.setClock(100000);
  delay(100);

  initializeBLE();

  const uint8_t deviceId = readRegister(WHO_AM_I_REG);
  Serial.print("WHO_AM_I = 0x"); Serial.println(deviceId, HEX);
  if (deviceId != 0x70) {
    Serial.println("ERROR: MPU-6500 not detected!");
    while (true) delay(1000);
  }
  initializeMPU6500();
  Serial.println("MPU-6500 detected and initialized.");

  windowQueue = xQueueCreate(2, sizeof(uint8_t));
  xTaskCreate(samplingTask, "SamplingTask", SAMPLING_TASK_STACK_BYTES, nullptr, SAMPLING_TASK_PRIORITY, nullptr);
  xTaskCreate(inferenceTask, "InferenceTask", INFERENCE_TASK_STACK_BYTES, nullptr, INFERENCE_TASK_PRIORITY, nullptr);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
