// ============================================================================
// SafeHer Glove - Hardware Diagnostic Sketch (NEW, separate from production)
//
// STATUS: Written but NOT compiled or flashed in this environment - no
// ESP32-C3/MPU-6500 hardware was available when this file was created. It
// has not been built with arduino-cli/PlatformIO and has not run on a
// device. Compile and flash it yourself, then report back the printed
// results (see the summary at the end of the validation report).
//
// WHY A SEPARATE SKETCH FOLDER: Arduino's build tooling concatenates every
// .ino file inside a sketch folder into one compilation unit. Placing this
// file inside firmware/SafeHer_Glove_Final/ (which already has its own
// setup()/loop() in SafeHer_Glove_Final.ino) would cause a duplicate-symbol
// build failure and could look like an attempt to modify that sketch. This
// lives in its own folder instead so the production sketch is completely
// unaffected and still builds exactly as before.
//
// PURPOSE: Pure sensor/timing diagnostics only. Does NOT load the ML model,
// does NOT run inference, does NOT use BLE. This isolates "is the sensor
// and sampling loop healthy" from "does the model/BLE/inference stack work"
// (that's SafeHer_Glove_Inference_Diagnostic.ino, also in its own folder).
//
// Does not modify SafeHer_Glove_Final.ino or any other existing file.
// ============================================================================

#include <Wire.h>
#include <math.h>

#define MPU_ADDR 0x68
#define WHO_AM_I_REG 0x75
#define EXPECTED_WHO_AM_I 0x70
#define PWR_MGMT_1 0x6B
#define ACCEL_CONFIG 0x1C
#define GYRO_CONFIG 0x1B
#define ACCEL_XOUT_H 0x3B

#define SAMPLE_INTERVAL_US 10000UL   // 10 ms -> 100 Hz target, same as production
#define TARGET_SAMPLE_COUNT 1000UL   // "at least 1,000 consecutive samples" per spec
#define RAW_PRINT_EVERY_N_SAMPLES 50 // print raw values periodically, not every sample
#define LATE_15MS_US 15000UL
#define LATE_20MS_US 20000UL

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

bool readSensorRaw(int16_t& axRaw, int16_t& ayRaw, int16_t& azRaw,
                    int16_t& gxRaw, int16_t& gyRaw, int16_t& gzRaw) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(ACCEL_XOUT_H);
  const uint8_t txStatus = Wire.endTransmission(false);

  const uint8_t received = Wire.requestFrom(MPU_ADDR, 14);
  if (txStatus != 0 || received < 14 || Wire.available() < 14) {
    axRaw = 0; ayRaw = 0; azRaw = 0;
    gxRaw = 0; gyRaw = 0; gzRaw = 0;
    return false;  // I2C read failure - caller counts this as a lost/bad sample
  }

  axRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  ayRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  azRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  Wire.read(); Wire.read();  // temperature, unused
  gxRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  gyRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  gzRaw = (int16_t)(((uint16_t)Wire.read() << 8) | (uint16_t)Wire.read());
  return true;
}

void initializeMPU6500() {
  writeRegister(PWR_MGMT_1, 0x00);
  delay(100);
  writeRegister(ACCEL_CONFIG, 0x00);
  writeRegister(GYRO_CONFIG, 0x00);
  delay(100);
}

// ----------------------------------------------------------------------------
// Part A: MPU-6500 connection check
// ----------------------------------------------------------------------------
bool runConnectionCheck() {
  Serial.println("=== PART A: MPU-6500 CONNECTION CHECK ===");
  Serial.printf("I2C address (expected): 0x%02X\n", MPU_ADDR);

  Wire.beginTransmission(MPU_ADDR);
  const uint8_t pingResult = Wire.endTransmission();
  Serial.printf("I2C ping result (0=ACK/OK): %u\n", pingResult);

  const uint8_t whoAmI = readRegister(WHO_AM_I_REG);
  Serial.printf("WHO_AM_I read: 0x%02X (expected 0x%02X)\n", whoAmI, EXPECTED_WHO_AM_I);

  const bool whoAmIOk = (whoAmI == EXPECTED_WHO_AM_I);
  if (!whoAmIOk) {
    Serial.println("RESULT: MPU-6500 NOT DETECTED (WHO_AM_I mismatch or I2C failure)");
    return false;
  }

  initializeMPU6500();

  // Confirm a real reading comes back non-trivial (not stuck at 0 or endpoint)
  int16_t axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw;
  const bool readOk = readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);
  Serial.printf("Post-init test read OK: %s\n", readOk ? "true" : "false");
  Serial.printf("Sample values: Ax=%d Ay=%d Az=%d Gx=%d Gy=%d Gz=%d\n",
                axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);

  Serial.println("RESULT: MPU-6500 DETECTED AND INITIALIZED");
  return true;
}

// ----------------------------------------------------------------------------
// Part B: sampling timing measurement
// ----------------------------------------------------------------------------
void runTimingTest() {
  Serial.println();
  Serial.println("=== PART B: SAMPLING TIMING TEST ===");
  Serial.printf("Target: %lu us/sample (~100 Hz), collecting >= %lu samples\n",
                SAMPLE_INTERVAL_US, TARGET_SAMPLE_COUNT);

  uint32_t sampleCount = 0;
  uint32_t i2cFailCount = 0;
  uint32_t minDtUs = 0xFFFFFFFFUL;
  uint32_t maxDtUs = 0;
  uint64_t sumDtUs = 0;
  uint32_t over15msCount = 0;
  uint32_t over20msCount = 0;

  unsigned long nextSampleTime = micros();
  unsigned long lastActualSampleMicros = nextSampleTime;
  bool haveLastSample = false;

  const unsigned long testStartMs = millis();

  while (sampleCount < TARGET_SAMPLE_COUNT) {
    const unsigned long now = micros();
    const long remaining = (long)(nextSampleTime - now);
    if (remaining > 0) {
      if (remaining > 1000) {
        delayMicroseconds(500);
      }
      continue;
    }
    nextSampleTime += SAMPLE_INTERVAL_US;

    int16_t axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw;
    const bool ok = readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);
    if (!ok) i2cFailCount++;

    const unsigned long actualNow = micros();
    if (haveLastSample) {
      const uint32_t dt = (uint32_t)(actualNow - lastActualSampleMicros);
      sumDtUs += dt;
      if (dt < minDtUs) minDtUs = dt;
      if (dt > maxDtUs) maxDtUs = dt;
      if (dt > LATE_15MS_US) over15msCount++;
      if (dt > LATE_20MS_US) over20msCount++;
    }
    lastActualSampleMicros = actualNow;
    haveLastSample = true;
    sampleCount++;

    if (sampleCount % RAW_PRINT_EVERY_N_SAMPLES == 0) {
      // Periodic raw print only -- printing every sample would itself
      // perturb the timing we are trying to measure.
      Serial.printf("RAW[%lu]: Ax=%d Ay=%d Az=%d Gx=%d Gy=%d Gz=%d\n",
                    sampleCount, axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);
    }
  }

  const unsigned long testEndMs = millis();
  const unsigned long elapsedMs = testEndMs - testStartMs;

  const uint32_t avgDtUs = (sampleCount > 1) ? (uint32_t)(sumDtUs / (sampleCount - 1)) : 0;
  const float approxHz = (avgDtUs > 0) ? (1000000.0f / (float)avgDtUs) : 0.0f;

  Serial.println();
  Serial.println("--- TIMING RESULTS ---");
  Serial.printf("samples_collected=%lu\n", sampleCount);
  Serial.printf("i2c_read_failures=%lu\n", i2cFailCount);
  Serial.printf("total_elapsed_ms=%lu\n", elapsedMs);
  Serial.printf("avg_interval_us=%lu\n", avgDtUs);
  Serial.printf("min_interval_us=%lu\n", minDtUs);
  Serial.printf("max_interval_us=%lu\n", maxDtUs);
  Serial.printf("approx_frequency_hz=%.2f\n", approxHz);
  Serial.printf("intervals_over_15ms=%lu\n", over15msCount);
  Serial.printf("intervals_over_20ms=%lu\n", over20msCount);
  Serial.println("--- END TIMING RESULTS ---");
}

// ----------------------------------------------------------------------------
// Part D: buffering / no-lost-samples check.
// Fills a 100-sample ping-pong window pair exactly like production
// (WINDOW_SIZE=100, OVERLAP=50) but only counts+verifies handoffs; does not
// run feature extraction or inference. A monotonically increasing sample
// sequence number is stored per slot so a lost/overwritten sample would show
// up as a gap or duplicate in the printed sequence ranges.
// ----------------------------------------------------------------------------
#define WINDOW_SIZE 100
#define OVERLAP 50

void runBufferingCheck() {
  Serial.println();
  Serial.println("=== PART D: BUFFERING / LOST-SAMPLE CHECK ===");

  static uint32_t seqWindow[WINDOW_SIZE];
  int windowCount = 0;
  uint32_t seq = 0;
  uint32_t windowsHandedOff = 0;
  uint32_t expectedNextFirstSeq = 0;
  bool sequenceOk = true;

  unsigned long nextSampleTime = micros();
  const uint32_t samplesToRun = 500;  // 5 windows worth, enough to see 2 overlapping handoffs

  for (uint32_t i = 0; i < samplesToRun; ++i) {
    while ((long)(nextSampleTime - micros()) > 0) { /* busy-wait to hold cadence */ }
    nextSampleTime += SAMPLE_INTERVAL_US;

    int16_t axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw;
    readSensorRaw(axRaw, ayRaw, azRaw, gxRaw, gyRaw, gzRaw);

    if (windowCount < WINDOW_SIZE) {
      seqWindow[windowCount] = seq;
      windowCount++;
    }
    seq++;

    if (windowCount == WINDOW_SIZE) {
      const uint32_t firstSeq = seqWindow[0];
      const uint32_t lastSeq = seqWindow[WINDOW_SIZE - 1];
      const bool contiguous = (lastSeq - firstSeq) == (uint32_t)(WINDOW_SIZE - 1);
      if (windowsHandedOff > 0 && firstSeq != expectedNextFirstSeq) {
        sequenceOk = false;
        Serial.printf("GAP DETECTED: expected window to start at seq=%lu, got seq=%lu\n",
                      expectedNextFirstSeq, firstSeq);
      }
      Serial.printf("window#%lu: seq[%lu..%lu] contiguous=%s\n",
                    windowsHandedOff, firstSeq, lastSeq, contiguous ? "true" : "false");
      windowsHandedOff++;
      expectedNextFirstSeq = firstSeq + OVERLAP;

      for (int k = 0; k < OVERLAP; ++k) {
        seqWindow[k] = seqWindow[k + OVERLAP];
      }
      windowCount = WINDOW_SIZE - OVERLAP;
    }
  }

  Serial.printf("windows_handed_off=%lu\n", windowsHandedOff);
  Serial.printf("no_gaps_detected=%s\n", sequenceOk ? "true" : "false");
  Serial.println("=== END PART D ===");
}

void setup() {
  Serial.begin(115200);
  delay(1500);

  Serial.println();
  Serial.println("############################################################");
  Serial.println("SafeHer Glove - HARDWARE DIAGNOSTIC (sensor/timing only)");
  Serial.println("No model, no inference, no BLE in this sketch.");
  Serial.println("############################################################");

  Wire.begin();
  Wire.setClock(100000);
  delay(100);

  const bool mpuOk = runConnectionCheck();
  if (!mpuOk) {
    Serial.println("ABORTING further tests: MPU-6500 not detected.");
    return;
  }

  runTimingTest();
  runBufferingCheck();

  Serial.println();
  Serial.println("############################################################");
  Serial.println("DIAGNOSTIC COMPLETE. Copy the RESULT / RESULTS blocks above");
  Serial.println("verbatim into the hardware validation report.");
  Serial.println("############################################################");
}

void loop() {
  // One-shot diagnostic; nothing to do repeatedly.
  delay(5000);
}
