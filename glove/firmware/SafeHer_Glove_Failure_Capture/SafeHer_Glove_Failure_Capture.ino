// ============================================================================
// SafeHer Glove - Failure Capture Diagnostic (NEW, separate from production)
//
// STATUS: Written but NOT compiled or flashed in this environment. Based on
// the same two-FreeRTOS-task architecture as SafeHer_Glove_Inference_Diagnostic
// (verified working on real hardware earlier this session: ~100Hz sampling,
// zero gaps during inference, ~31ms total inference time) with the same two
// required build fixes discovered this session:
//   arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc,PartitionScheme=huge_app
// (USB CDC On Boot must be Enabled or Serial produces no output at all; the
// full model needs the Huge APP partition scheme or the build overflows flash.)
//
// PURPOSE: capture everything needed to analyze a real-world false-FALL/
// TWISTING event after the fact:
//   - per window: window number, activity label, timestamp, predicted class,
//     confidence, all 7 class probabilities, all 51 features
//   - raw IMU samples (Ax..Gz) for every sample in the window, so the exact
//     physical motion behind any flagged window can be inspected
//
// ACTIVITY LABELING: send a line over Serial starting with "LABEL " (e.g.
// "LABEL NORMAL_WALK") at any time; every following output row is tagged
// with that label until the next LABEL command. This lets you narrate the
// physical test protocol (NORMAL_WALK, NORMAL_PICKUP, NORMAL_SIT_STAND,
// NORMAL_ARM_MOVEMENT, NORMAL_WRIST_MOVEMENT, TWISTING_SLOW, TWISTING_MEDIUM,
// TWISTING_FAST, ...) live, without needing to correlate timestamps by hand
// afterward. Reading the label command happens in the low-priority inference/
// output task only - never in the timing-critical sampling task.
//
// Does NOT modify SafeHer_Glove_Final.ino, its model files, or any other
// existing file. Model files here are byte-identical copies (SHA-256
// verified) of firmware/SafeHer_Glove_Final/'s, not modified.
// ============================================================================

#include <Wire.h>
#include <math.h>
#include <string.h>
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
#define FALL_CONFIDENCE_THRESHOLD 0.65f  // unchanged, reported only - not applied as a gate here

#define SAMPLING_TASK_PRIORITY 3
#define INFERENCE_TASK_PRIORITY 1
#define SAMPLING_TASK_STACK_BYTES 3072
#define INFERENCE_TASK_STACK_BYTES 12288  // slightly larger: this task now also prints raw samples + features

#define MAX_LABEL_LEN 32

const char* const CLASS_NAMES[NUM_CLASSES] = {
  "NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"
};

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

// Current activity label, set via "LABEL <name>" over Serial. Read/written
// only from the inference/output task (single-writer, single-reader on this
// single-core target - no lock needed for a plain char buffer swap here
// since it is only ever touched from this one task).
char currentLabel[MAX_LABEL_LEN] = "UNSET";

struct FeatureStats { float mean, std, minv, maxv, range, rms; };

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

// Byte-for-byte the same formulas/order as production.
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

// Softmax over the raw accumulated scores -> full 7-class probability vector
// (evaluate_forest()/predict_class() alone only ever expose the argmax
// class's own probability via predict_confidence(); this capture tool needs
// all 7, so it is computed here the same way predict_confidence() does it
// internally, just without discarding the non-argmax entries).
void softmaxAll(const float* scores, float* probsOut) {
  float maxScore = scores[0];
  for (int i = 1; i < NUM_CLASSES; ++i) if (scores[i] > maxScore) maxScore = scores[i];
  float sumExp = 0.0f;
  for (int i = 0; i < NUM_CLASSES; ++i) {
    probsOut[i] = expf(scores[i] - maxScore);
    sumExp += probsOut[i];
  }
  for (int i = 0; i < NUM_CLASSES; ++i) probsOut[i] /= sumExp;
}

// Non-blocking: reads at most one pending line per call, never waits.
// Recognizes "LABEL <name>"; anything else on a line is ignored (echoed for
// visibility, but does not affect currentLabel).
void pollSerialLabelCommand() {
  static char buf[64];
  static uint8_t len = 0;

  while (Serial.available() > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (len > 0) {
        buf[len] = '\0';
        if (strncmp(buf, "LABEL ", 6) == 0) {
          strncpy(currentLabel, buf + 6, MAX_LABEL_LEN - 1);
          currentLabel[MAX_LABEL_LEN - 1] = '\0';
          Serial.printf("LABEL_SET,%s\n", currentLabel);
        }
        len = 0;
      }
    } else if (len < sizeof(buf) - 1) {
      buf[len++] = c;
    }
  }
}

void printWindowCsvRow(uint32_t winNum, const float* features, const float* scores) {
  float probs[NUM_CLASSES];
  softmaxAll(scores, probs);
  int predictedClass = 0;
  float bestProb = probs[0];
  for (int i = 1; i < NUM_CLASSES; ++i) {
    if (probs[i] > bestProb) { bestProb = probs[i]; predictedClass = i; }
  }

  // WINDOW_ROW,window,label,timestamp_ms,pred_class,confidence,
  // proba_NORMAL,proba_JERK,proba_PUSH,proba_PULL,proba_SHAKING,proba_TWISTING,proba_FALL,
  // f0,f1,...,f50   (51 raw feature values, same order as extract_glove_features.py)
  Serial.printf("WINDOW_ROW,%lu,%s,%lu,%s,%.4f", winNum, currentLabel, millis(),
                CLASS_NAMES[predictedClass], bestProb);
  for (int i = 0; i < NUM_CLASSES; ++i) {
    Serial.printf(",%.6f", probs[i]);
  }
  for (int i = 0; i < FEATURE_COUNT; ++i) {
    Serial.printf(",%.6f", features[i]);
  }
  Serial.println();
}

void printRawWindowSamples(uint32_t winNum, const SensorWindow& w) {
  // RAW_ROW,window,label,sample_idx,Ax,Ay,Az,Gx,Gy,Gz  - one line per raw
  // sample in the window (all 100; the first 50 duplicate the previous
  // window's last 50 due to the 50-sample overlap - kept for simplicity and
  // robustness of post-hoc parsing rather than trying to de-duplicate here).
  for (int i = 0; i < WINDOW_SIZE; ++i) {
    Serial.printf("RAW_ROW,%lu,%s,%d,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f\n",
                  winNum, currentLabel, i, w.ax[i], w.ay[i], w.az[i], w.gx[i], w.gy[i], w.gz[i]);
  }
}

void inferenceTask(void* pvParameters) {
  static float features[FEATURE_COUNT];
  static float scores[NUM_CLASSES];

  for (;;) {
    uint8_t slot;
    if (xQueueReceive(windowQueue, &slot, portMAX_DELAY) != pdTRUE) continue;

    static SensorWindow localWindow;
    memcpy(&localWindow, &snapshotBuffer[slot], sizeof(SensorWindow));
    snapshotConsumed[slot] = true;

    for (int i = 0; i < FEATURE_COUNT; ++i) features[i] = 0.0f;
    extractWindowFeatures(localWindow, features);
    SafeHer::V5Embedded::evaluate_forest(features, scores);

    windowNumber++;
    printWindowCsvRow(windowNumber, features, scores);
    printRawWindowSamples(windowNumber, localWindow);

    pollSerialLabelCommand();
  }
}

void samplingTask(void* pvParameters) {
  unsigned long nextSampleTime = micros();
  uint8_t nextSnapshotSlot = 0;

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

  Serial.println("SafeHer Glove - FAILURE CAPTURE DIAGNOSTIC");
  Serial.println("Send 'LABEL <name>' over Serial to tag subsequent windows, e.g.:");
  Serial.println("  LABEL NORMAL_WALK");
  Serial.println("  LABEL TWISTING_SLOW");
  Serial.println("Output rows: WINDOW_ROW (features+probabilities) and RAW_ROW (per-sample IMU).");
  Serial.println("FALL threshold (reported only, not applied here): 0.65");

  Wire.begin();
  Wire.setClock(100000);
  delay(100);

  const uint8_t deviceId = readRegister(WHO_AM_I_REG);
  Serial.print("WHO_AM_I = 0x"); Serial.println(deviceId, HEX);
  if (deviceId != 0x70) {
    Serial.println("ERROR: MPU-6500 not detected!");
    while (true) delay(1000);
  }
  initializeMPU6500();
  Serial.println("MPU-6500 detected and initialized. Starting capture...");

  windowQueue = xQueueCreate(2, sizeof(uint8_t));
  xTaskCreate(samplingTask, "SamplingTask", SAMPLING_TASK_STACK_BYTES, nullptr, SAMPLING_TASK_PRIORITY, nullptr);
  xTaskCreate(inferenceTask, "InferenceTask", INFERENCE_TASK_STACK_BYTES, nullptr, INFERENCE_TASK_PRIORITY, nullptr);
}

void loop() {
  vTaskDelay(pdMS_TO_TICKS(1000));
}
