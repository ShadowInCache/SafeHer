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

// ============================================================================
// SafeHer Glove - Final On-Device Firmware
//
// This file is a timing/scheduling fix applied on top of
// firmware/SafeHer_Glove_V5_OnDevice/SafeHer_Glove_V5_OnDevice.ino.
//
// WHAT CHANGED vs V5_OnDevice: sensor sampling and model inference now run
// as two separate FreeRTOS tasks (inference-mode only) so a slow 4200-tree
// forest evaluation, feature extraction, Serial printing, or a BLE notify()
// can never delay the next 10 ms sensor read. See the accompanying report
// for the full rationale.
//
// WHAT DID NOT CHANGE: the 51-feature formulas, feature order, class order,
// window size (100) / step size (50) / sample interval (10 ms), the FALL
// confirmation algorithm, the FALL confidence threshold, the MPU-6500
// register configuration, and the embedded model (safeher_glove_final_model.*,
// copied byte-for-byte from safeher_v5_model.* except for the #include
// filename). DATA_COLLECTION_MODE behavior is also unchanged.
// ============================================================================

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
#define DATA_COLLECTION_MODE 0

// Verbose per-window debug (raw feature dump, per-prediction timing/heap,
// etc). Off by default per the "keep prediction output simple" requirement;
// flip to 1 for bring-up debugging only.
#define VERBOSE_DEBUG 0

#define BLE_DEVICE_NAME "SafeHer-Glove"
#define BLE_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_TELEMETRY_CHAR_UUID "33b4fb00-9c17-4ad2-8fc9-89ad6dbc76bd"

#define TELEMETRY_INTERVAL_MS 500UL

// Sampling-timing diagnostics (Step 4). Report once every REPORT_INTERVAL_
// SAMPLES actual samples (~5 s at 100 Hz). "Close to 10 ms" and "late" bands
// are configurable here without touching the sampling task itself.
#define REPORT_INTERVAL_SAMPLES 500UL
#define CLOSE_TOLERANCE_US 1000UL   // within +-1 ms of the 10 ms deadline
#define LATE_THRESHOLD_US 12000UL   // dt > 12 ms counts as "significantly late"

// FreeRTOS task tuning. Sampling must always win the CPU, so it runs at a
// strictly higher priority than inference/output; ESP32-C3 is single-core,
// so this priority gap (not core pinning) is what protects the sample
// schedule from a slow forest evaluation.
#define SAMPLING_TASK_PRIORITY 3
#define INFERENCE_TASK_PRIORITY 1
#define SAMPLING_TASK_STACK_BYTES 3072
#define INFERENCE_TASK_STACK_BYTES 8192

const char* const CLASS_NAMES[NUM_CLASSES] = {
  "NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"
};

struct FeatureStats {
  float mean;
  float std;
  float minv;
  float maxv;
  float range;
  float rms;
};

// ----------------------------------------------------------------------------
// Double-buffered window hand-off between the sampling task and the
// inference task (Step 8). The sampling task is the only writer of the
// "live" window below; on window completion it copies (memcpy, a few
// microseconds) into one of two ping-pong snapshot buffers and hands the
// slot index to the inference task over a small queue. The inference task
// is the only reader of a snapshot buffer once it owns that slot, and marks
// the slot consumed immediately after copying it into local feature-
// extraction scratch space, before running the (slow) forest evaluation.
// This means the sampling task never touches memory the inference task is
// reading, and vice versa.
// ----------------------------------------------------------------------------

// Live window, filled by the sampling task only.
float axWindow[WINDOW_SIZE];
float ayWindow[WINDOW_SIZE];
float azWindow[WINDOW_SIZE];
float gxWindow[WINDOW_SIZE];
float gyWindow[WINDOW_SIZE];
float gzWindow[WINDOW_SIZE];
int windowCount = 0;

struct SensorWindow {
  float ax[WINDOW_SIZE];
  float ay[WINDOW_SIZE];
  float az[WINDOW_SIZE];
  float gx[WINDOW_SIZE];
  float gy[WINDOW_SIZE];
  float gz[WINDOW_SIZE];
};

static SensorWindow snapshotBuffer[2];
static volatile bool snapshotConsumed[2] = {true, true};
static QueueHandle_t windowQueue = nullptr;

uint32_t predictionCounter = 0;
int fallConfirmationCount = 0;

// ----------------------------------------------------------------------------
// Sampling-timing diagnostics (Step 4). Written only by the sampling task,
// using plain 32-bit fields (atomic on this single-core RISC-V target), and
// handed to the inference/output task purely as a snapshot + ready flag --
// the sampling task performs no Serial I/O at all.
// ----------------------------------------------------------------------------
struct SamplingStats {
  uint32_t sampleCount;
  uint32_t minDtUs;
  uint32_t maxDtUs;
  uint64_t sumDtUs;
  uint32_t closeCount;
  uint32_t lateCount;
};

static volatile SamplingStats gStats = {0, 0xFFFFFFFFUL, 0, 0, 0, 0};
static volatile bool gDiagnosticsReady = false;
static SamplingStats gReportSnapshot;

// BLE telemetry hand-off (accel/gyro magnitude in physical units). The
// sampling task only computes these two floats and sets a "due" flag every
// TELEMETRY_INTERVAL_MS (cheap, no I/O); the actual sendTelemetry() BLE
// notify() call -- which, like Serial output, can take real time -- runs
// from the inference/output task instead, same as in the original
// V5_OnDevice firmware's intent, just moved off the sampling critical path.
static volatile float gLastAccelMagnitudeG = 0.0f;
static volatile float gLastGyroMagnitudeDps = 0.0f;
static volatile bool gTelemetryDue = false;

BLECharacteristic* bleResultCharacteristic = nullptr;
BLECharacteristic* bleTelemetryCharacteristic = nullptr;
volatile bool blePhoneConnected = false;
unsigned long lastTelemetryMs = 0;

class SafeHerBleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* server) override {
    blePhoneConnected = true;
    Serial.println("BLE: Phone connected");
  }

  void onDisconnect(BLEServer* server) override {
    blePhoneConnected = false;
    Serial.println("BLE: Phone disconnected");
    BLEDevice::startAdvertising();
    Serial.println("BLE: Advertising restarted");
  }
};

void initializeBLE() {
  Serial.println("BLE: Initializing...");

  BLEDevice::init(BLE_DEVICE_NAME);
  Serial.println("BLE: Device name = SafeHer-Glove");

  BLEServer* bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new SafeHerBleServerCallbacks());

  BLEService* bleService = bleServer->createService(BLE_SERVICE_UUID);
  bleResultCharacteristic = bleService->createCharacteristic(
      BLE_CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  bleResultCharacteristic->addDescriptor(new BLE2902());
  bleResultCharacteristic->setValue("CLASS=NORMAL,CONFIDENCE=0.0000");

  bleTelemetryCharacteristic = bleService->createCharacteristic(
      BLE_TELEMETRY_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  bleTelemetryCharacteristic->addDescriptor(new BLE2902());
  bleTelemetryCharacteristic->setValue("0.00,0.0");

  bleService->start();

  BLEAdvertising* bleAdvertising = BLEDevice::getAdvertising();
  bleAdvertising->addServiceUUID(BLE_SERVICE_UUID);
  bleAdvertising->setScanResponse(true);
  bleAdvertising->setMinPreferred(0x06);
  bleAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE: Advertising started");
}

// Payload format for the mobile app: CLASS=<name>,CONFIDENCE=<0-1, 4dp>.
// Raw classification + confidence only - NOT converted to SAFE/ABNORMAL/
// HIGH_RISK here; the app computes its own threat score from this plus
// heart-rate/other signals. predictedClass/confidence are passed in exactly
// as computed by predict_class()/predict_confidence() - unchanged.
void notifyClassification(int predictedClass, float confidence) {
  if (!blePhoneConnected || bleResultCharacteristic == nullptr) {
    return;
  }

  char message[48];
  snprintf(message, sizeof(message), "CLASS=%s,CONFIDENCE=%.4f",
           CLASS_NAMES[predictedClass], confidence);
  bleResultCharacteristic->setValue(message);
  bleResultCharacteristic->notify();
}

void sendTelemetry(float accelMagnitudeG, float gyroMagnitudeDps) {
  if (!blePhoneConnected || bleTelemetryCharacteristic == nullptr) {
    return;
  }

  char telem[24];
  snprintf(telem, sizeof(telem), "%.2f,%.1f",
           accelMagnitudeG,
           gyroMagnitudeDps);
  bleTelemetryCharacteristic->setValue(telem);
  bleTelemetryCharacteristic->notify();
}

#if DATA_COLLECTION_MODE
// TEMP_SENSOR_DIAGNOSTIC
uint32_t badSensorSampleCount = 0;

void printRawSensorRow(int16_t axRaw, int16_t ayRaw, int16_t azRaw,
                       int16_t gxRaw, int16_t gyRaw, int16_t gzRaw) {
  // TEMP_SENSOR_DIAGNOSTIC
  const bool hasEndpointValue =
      axRaw == INT16_MIN || axRaw == INT16_MAX ||
      ayRaw == INT16_MIN || ayRaw == INT16_MAX ||
      azRaw == INT16_MIN || azRaw == INT16_MAX ||
      gxRaw == INT16_MIN || gxRaw == INT16_MAX ||
      gyRaw == INT16_MIN || gyRaw == INT16_MAX ||
      gzRaw == INT16_MIN || gzRaw == INT16_MAX;

  if (hasEndpointValue) {
    badSensorSampleCount++;
    Serial.print("SENSOR_BAD,");
    Serial.print(millis());
    Serial.print(",");
    Serial.print(axRaw);
    Serial.print(",");
    Serial.print(ayRaw);
    Serial.print(",");
    Serial.print(azRaw);
    Serial.print(",");
    Serial.print(gxRaw);
    Serial.print(",");
    Serial.print(gyRaw);
    Serial.print(",");
    Serial.println(gzRaw);
    Serial.print("SENSOR_BAD_TOTAL,");
    Serial.println(badSensorSampleCount);
  }

  Serial.print(millis());
  Serial.print(",");
  Serial.print(axRaw);
  Serial.print(",");
  Serial.print(ayRaw);
  Serial.print(",");
  Serial.print(azRaw);
  Serial.print(",");
  Serial.print(gxRaw);
  Serial.print(",");
  Serial.print(gyRaw);
  Serial.print(",");
  Serial.println(gzRaw);
}
#endif

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
  if (Wire.available()) {
    return Wire.read();
  }

  return 0xFF;
}

void readSensorRaw(int16_t& axRaw, int16_t& ayRaw, int16_t& azRaw,
                  int16_t& gxRaw, int16_t& gyRaw, int16_t& gzRaw) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(ACCEL_XOUT_H);
  Wire.endTransmission(false);

  Wire.requestFrom(MPU_ADDR, 14);
  if (Wire.available() < 14) {
    axRaw = 0; ayRaw = 0; azRaw = 0;
    gxRaw = 0; gyRaw = 0; gzRaw = 0;
    return;
  }

  axRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  ayRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  azRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());

  // Temperature bytes; identified by the original collector and not used.
  Wire.read();
  Wire.read();

  gxRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  gyRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  gzRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
}

// Unchanged formulas: population (ddof=0) mean/std, min, max, range, rms.
void computeStats(const float* values, int len, FeatureStats& stats) {
  if (len <= 0) {
    stats.mean = 0.0f;
    stats.std = 0.0f;
    stats.minv = 0.0f;
    stats.maxv = 0.0f;
    stats.range = 0.0f;
    stats.rms = 0.0f;
    return;
  }

  float sum = 0.0f;
  float sumSquares = 0.0f;
  float minv = values[0];
  float maxv = values[0];

  for (int i = 0; i < len; ++i) {
    const float v = values[i];
    sum += v;
    sumSquares += v * v;
    if (v < minv) minv = v;
    if (v > maxv) maxv = v;
  }

  const float mean = sum / (float)len;
  float variance = 0.0f;
  for (int i = 0; i < len; ++i) {
    const float diff = values[i] - mean;
    variance += diff * diff;
  }
  variance /= (float)len;

  stats.mean = mean;
  stats.std = sqrtf(variance);
  stats.minv = minv;
  stats.maxv = maxv;
  stats.range = maxv - minv;
  stats.rms = sqrtf(sumSquares / (float)len);
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

// Same 51-feature extraction as V5_OnDevice, byte-for-byte identical
// formulas and ordering -- only the data source changed, from the global
// live window to a caller-supplied snapshot (SensorWindow), since by the
// time this runs the sampling task has already moved on to filling the
// next live window.
void extractWindowFeatures(const SensorWindow& window, float* features) {
  int idx = 0;

  addStats(features, idx, window.ax, WINDOW_SIZE);
  addStats(features, idx, window.ay, WINDOW_SIZE);
  addStats(features, idx, window.az, WINDOW_SIZE);
  addStats(features, idx, window.gx, WINDOW_SIZE);
  addStats(features, idx, window.gy, WINDOW_SIZE);
  addStats(features, idx, window.gz, WINDOW_SIZE);

  float accMag[WINDOW_SIZE];
  float gyroMag[WINDOW_SIZE];
  for (int i = 0; i < WINDOW_SIZE; ++i) {
    accMag[i] = sqrtf(window.ax[i] * window.ax[i] +
                      window.ay[i] * window.ay[i] +
                      window.az[i] * window.az[i]);
    gyroMag[i] = sqrtf(window.gx[i] * window.gx[i] +
                       window.gy[i] * window.gy[i] +
                       window.gz[i] * window.gz[i]);
  }

  addStats(features, idx, accMag, WINDOW_SIZE);
  addStats(features, idx, gyroMag, WINDOW_SIZE);

  float jerk[WINDOW_SIZE - 1];
  for (int i = 0; i < WINDOW_SIZE - 1; ++i) {
    jerk[i] = accMag[i + 1] - accMag[i];
  }

  FeatureStats jerkStats;
  computeStats(jerk, WINDOW_SIZE - 1, jerkStats);
  features[idx++] = jerkStats.mean;
  features[idx++] = jerkStats.std;
  features[idx++] = jerkStats.maxv;

  while (idx < FEATURE_COUNT) {
    features[idx++] = 0.0f;
  }
}

#if VERBOSE_DEBUG
void printDebugFeatures(const float* features, int predictedClass, float confidence) {
  Serial.println("DEBUG:");
  Serial.printf("class=%s\n", CLASS_NAMES[predictedClass]);
  Serial.printf("confidence=%.2f\n", confidence);
  Serial.printf("acc_mag_max=%.6f\n", features[39]);
  Serial.printf("acc_mag_range=%.6f\n", features[40]);
  Serial.printf("acc_mag_rms=%.6f\n", features[41]);
  Serial.printf("gyro_mag_max=%.6f\n", features[45]);
  Serial.printf("gyro_mag_range=%.6f\n", features[46]);
  Serial.printf("gyro_mag_rms=%.6f\n", features[47]);
  Serial.printf("jerk_max=%.6f\n", features[50]);
  Serial.printf("Ax_range=%.6f\n", features[4]);
  Serial.printf("Ay_range=%.6f\n", features[10]);
  Serial.printf("Az_range=%.6f\n", features[16]);
  Serial.printf("Gx_range=%.6f\n", features[22]);
  Serial.printf("Gy_range=%.6f\n", features[28]);
  Serial.printf("Gz_range=%.6f\n", features[34]);
}
#endif

// TEMPORARY DIAGNOSTIC (false-FALL investigation): full 7-class softmax
// probability vector. evaluate_forest()/predict_class()/predict_confidence()
// are unchanged and untouched - this only re-applies the same softmax math
// predict_confidence() already uses internally, without discarding the
// non-argmax entries, so every class's probability can be inspected, not
// just the winning one. Does not alter the model or the argmax decision.
void softmaxAllClasses(const float* scores, float* probsOut) {
  float maxScore = scores[0];
  for (int i = 1; i < NUM_CLASSES; ++i) {
    if (scores[i] > maxScore) maxScore = scores[i];
  }
  float sumExp = 0.0f;
  for (int i = 0; i < NUM_CLASSES; ++i) {
    probsOut[i] = expf(scores[i] - maxScore);
    sumExp += probsOut[i];
  }
  for (int i = 0; i < NUM_CLASSES; ++i) {
    probsOut[i] /= sumExp;
  }
}

// TEMPORARY DIAGNOSTIC (false-FALL investigation): per-window prediction +
// full probability dump, requested format. Remove once the investigation is
// done; does not affect predictedClass/confidence/safetyText/BLE, which are
// computed exactly as before and passed in unchanged.
void printDiagnosticWindow(uint32_t windowNum, int predictedClass, float confidence, const float* probs) {
  Serial.printf("WINDOW=%lu\n", windowNum);
  Serial.printf("PREDICTED=%s\n", CLASS_NAMES[predictedClass]);
  Serial.printf("CONFIDENCE=%.4f\n", confidence);
  Serial.printf("P_NORMAL=%.4f\n", probs[0]);
  Serial.printf("P_JERK=%.4f\n", probs[1]);
  Serial.printf("P_PUSH=%.4f\n", probs[2]);
  Serial.printf("P_PULL=%.4f\n", probs[3]);
  Serial.printf("P_SHAKING=%.4f\n", probs[4]);
  Serial.printf("P_TWISTING=%.4f\n", probs[5]);
  Serial.printf("P_FALL=%.4f\n", probs[6]);
}

// Step 5 output: two short lines, unchanged FALL-confirmation algorithm.
void printStatus(int predictedClass, const char* safetyText) {
  if (predictedClass == 0) {
    Serial.println("SAFEHER STATUS: NORMAL");
  } else {
    Serial.println("SAFEHER STATUS: ABNORMAL");
    Serial.printf("Motion: %s\n", CLASS_NAMES[predictedClass]);
  }
}

// FALL confirmation: 2-hit debounce at >= threshold. See
// firmware/SafeHer_Glove_Final/FALL_CONFIRMATION_3HIT_EXPERIMENT.md for the
// rationale, the offline simulation this was based on, and how to revert.
const char* applyFallConfirmation(int predictedClass, float confidence) {
  if (predictedClass != 6) {
    fallConfirmationCount = 0;
    return (predictedClass == 0) ? "SAFE" : "ABNORMAL";
  }

  if (confidence >= FALL_CONFIDENCE_THRESHOLD) {
    fallConfirmationCount++;
  } else {
    fallConfirmationCount = 0;
  }

  return (fallConfirmationCount >= 2) ? "HIGH_RISK" : "ABNORMAL";
}

void printSamplingDiagnostics(const SamplingStats& stats) {
  const uint32_t avgDtUs = (stats.sampleCount > 0)
      ? (uint32_t)(stats.sumDtUs / stats.sampleCount)
      : 0;
  const uint32_t minDtUs = (stats.sampleCount > 0) ? stats.minDtUs : 0;

  Serial.println("SAMPLING:");
  Serial.printf("samples=%u\n", stats.sampleCount);
  Serial.printf("avg_dt=%u us\n", avgDtUs);
  Serial.printf("min_dt=%u us\n", minDtUs);
  Serial.printf("max_dt=%u us\n", stats.maxDtUs);
  Serial.printf("close_to_10ms=%u\n", stats.closeCount);
  Serial.printf("late_samples=%u\n", stats.lateCount);
  Serial.printf("max_gap=%u us\n", stats.maxDtUs);
}

// ----------------------------------------------------------------------------
// Inference / output task (LOW priority). Blocks on the window queue,
// so it does no work at all until the sampling task hands it a completed
// window; everything slow (feature extraction, 4200-tree forest
// evaluation, Serial output, BLE notify) lives here, off the sampling
// task's critical path.
// ----------------------------------------------------------------------------
void inferenceTask(void* pvParameters) {
  static float features[FEATURE_COUNT];
  static float scores[NUM_CLASSES];

  for (;;) {
    uint8_t slot;
    if (xQueueReceive(windowQueue, &slot, portMAX_DELAY) != pdTRUE) {
      continue;
    }

    // Copy out of the shared snapshot buffer first, then release it
    // immediately -- the sampling task may reuse this slot as soon as
    // snapshotConsumed[slot] is set, well before the (slower) forest
    // evaluation below runs.
    static SensorWindow localWindow;
    memcpy(&localWindow, &snapshotBuffer[slot], sizeof(SensorWindow));
    snapshotConsumed[slot] = true;

    for (int i = 0; i < FEATURE_COUNT; ++i) {
      features[i] = 0.0f;
    }

    extractWindowFeatures(localWindow, features);
    SafeHer::V5Embedded::evaluate_forest(features, scores);

    const int predictedClass = SafeHer::V5Embedded::predict_class(scores);
    const float confidence = SafeHer::V5Embedded::predict_confidence(scores);

    const char* safetyText = applyFallConfirmation(predictedClass, confidence);

    // TEMPORARY DIAGNOSTIC (false-FALL investigation): full probability dump
    // for every window, requested format. predictedClass/confidence/
    // safetyText above are unchanged - this only prints them plus the full
    // softmax vector alongside the existing printStatus() call below.
    float diagnosticProbs[NUM_CLASSES];
    softmaxAllClasses(scores, diagnosticProbs);
    printDiagnosticWindow(predictionCounter, predictedClass, confidence, diagnosticProbs);

#if VERBOSE_DEBUG
    printDebugFeatures(features, predictedClass, confidence);
    Serial.printf("RAW: %s | Confidence: %.2f | FALL_COUNT: %d\n",
                  CLASS_NAMES[predictedClass], confidence, fallConfirmationCount);
    Serial.printf("SAFETY: %s\n", safetyText);
#else
    (void)safetyText;
#endif

    printStatus(predictedClass, safetyText);
    notifyClassification(predictedClass, confidence);
    predictionCounter++;

    if (gDiagnosticsReady) {
      printSamplingDiagnostics(gReportSnapshot);
      gDiagnosticsReady = false;
    }

    if (gTelemetryDue) {
      gTelemetryDue = false;
      sendTelemetry(gLastAccelMagnitudeG, gLastGyroMagnitudeDps);
    }
  }
}

// ----------------------------------------------------------------------------
// Sampling task (HIGH priority). Deadline-scheduled 100 Hz sensor
// acquisition. No feature extraction, no model inference, and no Serial
// I/O happens here -- only I2C reads, buffer writes, and (once every 50
// samples) a fast memcpy handoff to the inference task. Because this task
// runs at a strictly higher FreeRTOS priority than the inference task, it
// always preempts a slow forest evaluation at the next scheduler tick
// (1 ms default) instead of waiting behind it.
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
      // Not due yet. Sleep in 1-tick (~1 ms) increments while there is
      // more than a tick of slack, then busy-poll the last stretch for
      // precision. This task's priority guarantees it is never starved
      // by the (lower-priority) inference task while waiting.
      if (remaining > 1000) {
        vTaskDelay(1);
      }
      continue;
    }

    nextSampleTime += SAMPLE_INTERVAL_US;

    int16_t axRaw = 0, ayRaw = 0, azRaw = 0;
    int16_t gxRaw = 0, gyRaw = 0, gzRaw = 0;
    readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);

    {
      // Cheap float math only -- no I/O -- so this cannot delay the next
      // sample deadline. The actual BLE notify() happens in inferenceTask.
      const float axG = (float)axRaw / 16384.0f;
      const float ayG = (float)ayRaw / 16384.0f;
      const float azG = (float)azRaw / 16384.0f;
      const float gxDps = (float)gxRaw / 131.0f;
      const float gyDps = (float)gyRaw / 131.0f;
      const float gzDps = (float)gzRaw / 131.0f;
      gLastAccelMagnitudeG = sqrtf(axG * axG + ayG * ayG + azG * azG);
      gLastGyroMagnitudeDps = sqrtf(gxDps * gxDps + gyDps * gyDps + gzDps * gzDps);

      const unsigned long nowMs = millis();
      if ((nowMs - lastTelemetryMs) >= TELEMETRY_INTERVAL_MS) {
        lastTelemetryMs = nowMs;
        gTelemetryDue = true;
      }
    }

    // Timing diagnostics: measured between actual samples taken, not
    // between scheduled deadlines, so a run of back-to-back catch-up
    // reads (if it ever happens again) would show up as small dt values
    // followed by the late/max_gap counters, rather than being hidden.
    const unsigned long actualNow = micros();
    if (haveLastSample) {
      const uint32_t dt = (uint32_t)(actualNow - lastActualSampleMicros);
      gStats.sampleCount++;
      gStats.sumDtUs += dt;
      if (dt < gStats.minDtUs) gStats.minDtUs = dt;
      if (dt > gStats.maxDtUs) gStats.maxDtUs = dt;
      if (dt <= SAMPLE_INTERVAL_US + CLOSE_TOLERANCE_US &&
          dt + CLOSE_TOLERANCE_US >= SAMPLE_INTERVAL_US) {
        gStats.closeCount++;
      }
      if (dt > LATE_THRESHOLD_US) {
        gStats.lateCount++;
      }

      if (gStats.sampleCount >= REPORT_INTERVAL_SAMPLES && !gDiagnosticsReady) {
        gReportSnapshot.sampleCount = gStats.sampleCount;
        gReportSnapshot.minDtUs = gStats.minDtUs;
        gReportSnapshot.maxDtUs = gStats.maxDtUs;
        gReportSnapshot.sumDtUs = gStats.sumDtUs;
        gReportSnapshot.closeCount = gStats.closeCount;
        gReportSnapshot.lateCount = gStats.lateCount;
        gDiagnosticsReady = true;

        gStats.sampleCount = 0;
        gStats.minDtUs = 0xFFFFFFFFUL;
        gStats.maxDtUs = 0;
        gStats.sumDtUs = 0;
        gStats.closeCount = 0;
        gStats.lateCount = 0;
      }
    }
    lastActualSampleMicros = actualNow;
    haveLastSample = true;

    if (windowCount < WINDOW_SIZE) {
      axWindow[windowCount] = (float)axRaw;
      ayWindow[windowCount] = (float)ayRaw;
      azWindow[windowCount] = (float)azRaw;
      gxWindow[windowCount] = (float)gxRaw;
      gyWindow[windowCount] = (float)gyRaw;
      gzWindow[windowCount] = (float)gzRaw;
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

        // Non-blocking send: if the inference task has somehow fallen
        // behind by more than two full windows (it should not, given
        // forest evaluation is single-digit-to-tens of ms and a new
        // window is only due every 500 ms), drop this window rather than
        // ever let sampling wait.
        xQueueSend(windowQueue, &nextSnapshotSlot, 0);
        nextSnapshotSlot = 1 - nextSnapshotSlot;
      }
      // else: inference task has not yet consumed the slot we would reuse
      // (should not happen in practice -- see comment above). Skip this
      // window's handoff rather than corrupt a buffer still being read;
      // sampling itself continues uninterrupted either way.

      for (int i = 0; i < OVERLAP; ++i) {
        axWindow[i] = axWindow[i + OVERLAP];
        ayWindow[i] = ayWindow[i + OVERLAP];
        azWindow[i] = azWindow[i + OVERLAP];
        gxWindow[i] = gxWindow[i + OVERLAP];
        gyWindow[i] = gyWindow[i + OVERLAP];
        gzWindow[i] = gzWindow[i + OVERLAP];
      }
      windowCount = WINDOW_SIZE - OVERLAP;
    }

#if DATA_COLLECTION_MODE
    // Not reachable: samplingTask only runs when DATA_COLLECTION_MODE is 0
    // (see setup()). Left out intentionally -- collection mode keeps using
    // the original single-loop path below, unchanged.
#endif
  }
}

void initializeMPU6500() {
  writeRegister(PWR_MGMT_1, 0x00);
  delay(100);

  writeRegister(ACCEL_CONFIG, 0x00);
  writeRegister(GYRO_CONFIG, 0x00);
  delay(100);
}

void setup() {
  Serial.begin(115200);
  delay(1500);

  fallConfirmationCount = 0;

  Wire.begin();
  Wire.setClock(100000);
  delay(100);

#if DATA_COLLECTION_MODE
  const uint8_t deviceId = readRegister(WHO_AM_I_REG);
  if (deviceId != 0x70) {
    while (true) {
      delay(1000);
    }
  }

  initializeMPU6500();
  Serial.println("timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz");
#else
  Serial.println("SafeHer Glove Final On-Device Inference");
  Serial.println("ESP32-C3");
  Serial.println("MPU-6500");
  Serial.println("100 Hz");
  Serial.println("Window: 100 samples");
  Serial.println("Overlap: 50 samples");
  Serial.println("Features: 51");
  Serial.println("Classes: 7");
  Serial.println("FALL threshold: 0.65");
  Serial.println("Sampling: dedicated high-priority task, decoupled from inference");

  initializeBLE();

  const uint8_t deviceId = readRegister(WHO_AM_I_REG);
  Serial.print("WHO_AM_I = 0x");
  Serial.println(deviceId, HEX);

  if (deviceId != 0x70) {
    Serial.println("ERROR: MPU-6500 not detected!");
    while (true) {
      delay(1000);
    }
  }

  initializeMPU6500();
  Serial.println("MPU-6500 detected and initialized.");

  windowQueue = xQueueCreate(2, sizeof(uint8_t));
  if (windowQueue == nullptr) {
    Serial.println("ERROR: failed to create window queue");
  }

  const BaseType_t samplingTaskCreated = xTaskCreate(
      samplingTask, "SamplingTask", SAMPLING_TASK_STACK_BYTES,
      nullptr, SAMPLING_TASK_PRIORITY, nullptr);
  const BaseType_t inferenceTaskCreated = xTaskCreate(
      inferenceTask, "InferenceTask", INFERENCE_TASK_STACK_BYTES,
      nullptr, INFERENCE_TASK_PRIORITY, nullptr);
  if (samplingTaskCreated != pdPASS || inferenceTaskCreated != pdPASS) {
    Serial.println("ERROR: failed to create sampling/inference task(s)");
  }
#endif
}

void loop() {
#if DATA_COLLECTION_MODE
  // Unchanged from V5_OnDevice: single-loop, deadline-scheduled per-sample
  // CSV printing. Not the code path this fix targets -- collection-mode
  // timing was not found to be a problem (lightweight, one Serial.print
  // per sample, no model inference in this branch).
  static unsigned long nextSampleTime = micros();
  const unsigned long now = micros();
  if ((long)(now - nextSampleTime) >= 0) {
    nextSampleTime += SAMPLE_INTERVAL_US;

    int16_t axRaw = 0, ayRaw = 0, azRaw = 0;
    int16_t gxRaw = 0, gyRaw = 0, gzRaw = 0;
    readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);
    printRawSensorRow(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);
  }
#else
  // All real work happens in samplingTask/inferenceTask. Nothing for the
  // default Arduino loop task to do; sleep so it doesn't spin and steal
  // cycles from the two tasks that matter.
  vTaskDelay(pdMS_TO_TICKS(1000));
#endif
}
