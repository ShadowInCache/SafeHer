#include <Wire.h>
#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "safeher_v5_model.h"

#define MPU_ADDR 0x68
#define WHO_AM_I_REG 0x75
#define PWR_MGMT_1 0x6B
#define ACCEL_CONFIG 0x1C
#define GYRO_CONFIG 0x1B
#define ACCEL_XOUT_H 0x3B

#define SAMPLE_INTERVAL_US 10000UL
#define WINDOW_SIZE 100
#define OVERLAP 50
#define NUM_CLASSES 5
#define FALL_CLASS_INDEX (NUM_CLASSES - 1)  // FALL is always the last class in CLASS_NAMES
#define FEATURE_COUNT 51
#define FALL_CONFIDENCE_THRESHOLD 0.65f
#define DEBUG_FEATURES 1
#define DATA_COLLECTION_MODE 0

#define BLE_DEVICE_NAME "SafeHer-Glove"
#define BLE_SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define BLE_CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define BLE_TELEMETRY_CHAR_UUID "33b4fb00-9c17-4ad2-8fc9-89ad6dbc76bd"

#define TELEMETRY_INTERVAL_MS 500UL

const char* const CLASS_NAMES[NUM_CLASSES] = {
  "NORMAL", "SUDDEN_MOVEMENT", "SHAKING", "TWISTING", "FALL"
};

struct FeatureStats {
  float mean;
  float std;
  float minv;
  float maxv;
  float range;
  float rms;
};

float axWindow[WINDOW_SIZE];
float ayWindow[WINDOW_SIZE];
float azWindow[WINDOW_SIZE];
float gxWindow[WINDOW_SIZE];
float gyWindow[WINDOW_SIZE];
float gzWindow[WINDOW_SIZE];

int windowCount = 0;
uint32_t predictionCounter = 0;
unsigned long nextSampleTime = 0;
int fallConfirmationCount = 0;

// TEMP_SENSOR_DIAGNOSTIC
int16_t diagnosticAxRaw = 0;
int16_t diagnosticAyRaw = 0;
int16_t diagnosticAzRaw = 0;
int16_t diagnosticGxRaw = 0;
int16_t diagnosticGyRaw = 0;
int16_t diagnosticGzRaw = 0;

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
  bleResultCharacteristic->setValue("NORMAL,0.00");

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

void notifyClassification(int predictedClass, float confidence) {
  if (!blePhoneConnected || bleResultCharacteristic == nullptr) {
    return;
  }

  char message[32];
  snprintf(message, sizeof(message), "%s,%.2f",
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

void extractWindowFeatures(float* features) {
  int idx = 0;

  addStats(features, idx, axWindow, WINDOW_SIZE);
  addStats(features, idx, ayWindow, WINDOW_SIZE);
  addStats(features, idx, azWindow, WINDOW_SIZE);
  addStats(features, idx, gxWindow, WINDOW_SIZE);
  addStats(features, idx, gyWindow, WINDOW_SIZE);
  addStats(features, idx, gzWindow, WINDOW_SIZE);

  float accMag[WINDOW_SIZE];
  float gyroMag[WINDOW_SIZE];
  for (int i = 0; i < WINDOW_SIZE; ++i) {
    accMag[i] = sqrtf(axWindow[i] * axWindow[i] +
                      ayWindow[i] * ayWindow[i] +
                      azWindow[i] * azWindow[i]);
    gyroMag[i] = sqrtf(gxWindow[i] * gxWindow[i] +
                       gyWindow[i] * gyWindow[i] +
                       gzWindow[i] * gzWindow[i]);
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

#if DEBUG_FEATURES
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

void printPredictionSummary(uint32_t id, int predictedClass, float confidence, const char* safetyText) {
  Serial.printf("[%04u] %s | Class: %s | Confidence: %.2f\n",
                id,
                safetyText,
                CLASS_NAMES[predictedClass],
                confidence);
}

const char* applyFallConfirmation(int predictedClass, float confidence) {
  if (predictedClass != FALL_CLASS_INDEX) {
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

void classifyPrediction(const float* scores, const float confidence) {
  const int predictedClass = SafeHer::V5Embedded::predict_class(scores);
  const float predictedConfidence = confidence;

  const char* safetyText = applyFallConfirmation(predictedClass, predictedConfidence);

  printPredictionSummary(predictionCounter, predictedClass, predictedConfidence, safetyText);
}

void runInference() {
  float features[FEATURE_COUNT];
  float scores[NUM_CLASSES];

  for (int i = 0; i < FEATURE_COUNT; ++i) {
    features[i] = 0.0f;
  }

  uint32_t heapBefore = ESP.getFreeHeap();
  uint32_t startMicros = micros();

  extractWindowFeatures(features);
  SafeHer::V5Embedded::evaluate_forest(features, scores);

  const int predictedClass = SafeHer::V5Embedded::predict_class(scores);
  const float confidence = SafeHer::V5Embedded::predict_confidence(scores);
  uint32_t endMicros = micros();
#if DEBUG_FEATURES
  printDebugFeatures(features, predictedClass, confidence);
#endif
  // TEMP_SENSOR_DIAGNOSTIC
  Serial.printf("TEMP_SENSOR_DIAGNOSTIC raw_signed: ax_raw=%d ay_raw=%d az_raw=%d gx_raw=%d gy_raw=%d gz_raw=%d\n",
                diagnosticAxRaw, diagnosticAyRaw, diagnosticAzRaw,
                diagnosticGxRaw, diagnosticGyRaw, diagnosticGzRaw);
  Serial.printf("TEMP_SENSOR_DIAGNOSTIC converted_float: ax=%.1f ay=%.1f az=%.1f gx=%.1f gy=%.1f gz=%.1f\n",
                (float)diagnosticAxRaw, (float)diagnosticAyRaw, (float)diagnosticAzRaw,
                (float)diagnosticGxRaw, (float)diagnosticGyRaw, (float)diagnosticGzRaw);
  Serial.printf("TEMP_SENSOR_DIAGNOSTIC window_minmax: Ax=[%.1f,%.1f] Ay=[%.1f,%.1f] Az=[%.1f,%.1f] Gx=[%.1f,%.1f] Gy=[%.1f,%.1f] Gz=[%.1f,%.1f]\n",
                features[2], features[3], features[8], features[9], features[14], features[15],
                features[20], features[21], features[26], features[27], features[32], features[33]);
  uint32_t heapAfter = ESP.getFreeHeap();

  const char* safetyText = applyFallConfirmation(predictedClass, confidence);

  Serial.printf("Inference time: %.2f ms\n", (endMicros - startMicros) / 1000.0f);
  Serial.printf("Free heap before inference: %u bytes\n", heapBefore);
  Serial.printf("Free heap after inference: %u bytes\n", heapAfter);

  Serial.printf("RAW: %s | Confidence: %.2f | FALL_COUNT: %d\n",
                CLASS_NAMES[predictedClass], confidence, fallConfirmationCount);
  if (predictedClass == FALL_CLASS_INDEX && fallConfirmationCount < 2) {
    Serial.println("SAFETY: FALL CANDIDATE");
  } else if (predictedClass == FALL_CLASS_INDEX) {
    Serial.println("SAFETY: HIGH_RISK - FALL CONFIRMED");
  } else {
    Serial.printf("SAFETY: %s\n", safetyText);
  }

  printPredictionSummary(predictionCounter, predictedClass, confidence, safetyText);
  notifyClassification(predictedClass, confidence);
  predictionCounter++;
}

void enqueueSample(int16_t ax, int16_t ay, int16_t az, int16_t gx, int16_t gy, int16_t gz) {
  if (windowCount < WINDOW_SIZE) {
    axWindow[windowCount] = (float)ax;
    ayWindow[windowCount] = (float)ay;
    azWindow[windowCount] = (float)az;
    gxWindow[windowCount] = (float)gx;
    gyWindow[windowCount] = (float)gy;
    gzWindow[windowCount] = (float)gz;
    windowCount++;
  }

  if (windowCount == WINDOW_SIZE) {
    runInference();

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
  Serial.println("SafeHer Glove V5 On-Device Inference");
  Serial.println("ESP32-C3");
  Serial.println("MPU-6500");
  Serial.println("100 Hz");
  Serial.println("Window: 100 samples");
  Serial.println("Overlap: 50 samples");
  Serial.println("Features: 51");
  Serial.println("Classes: 7");
  Serial.println("FALL threshold: 0.65");

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
#endif

  nextSampleTime = micros();
}

void loop() {
  const unsigned long now = micros();
  if ((long)(now - nextSampleTime) >= 0) {
    nextSampleTime += SAMPLE_INTERVAL_US;

    int16_t axRaw = 0, ayRaw = 0, azRaw = 0;
    int16_t gxRaw = 0, gyRaw = 0, gzRaw = 0;
    readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);

    const float axG = (float)axRaw / 16384.0f;
    const float ayG = (float)ayRaw / 16384.0f;
    const float azG = (float)azRaw / 16384.0f;
    const float gxDps = (float)gxRaw / 131.0f;
    const float gyDps = (float)gyRaw / 131.0f;
    const float gzDps = (float)gzRaw / 131.0f;
    const float accelMagnitudeG = sqrtf(axG * axG + ayG * ayG + azG * azG);
    const float gyroMagnitudeDps = sqrtf(gxDps * gxDps + gyDps * gyDps + gzDps * gzDps);

  #if DATA_COLLECTION_MODE
    printRawSensorRow(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);
  #else
    // TEMP_SENSOR_DIAGNOSTIC
    diagnosticAxRaw = axRaw;
    diagnosticAyRaw = ayRaw;
    diagnosticAzRaw = azRaw;
    diagnosticGxRaw = gxRaw;
    diagnosticGyRaw = gyRaw;
    diagnosticGzRaw = gzRaw;

    enqueueSample(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);

    if ((millis() - lastTelemetryMs) >= TELEMETRY_INTERVAL_MS) {
      lastTelemetryMs = millis();
      sendTelemetry(accelMagnitudeG, gyroMagnitudeDps);
    }
#endif
  }
}
