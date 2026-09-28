// SafeHer glove - minimal MAX30102 driver (heart-rate sensor).
//
// Register-level, on the SAME Wire (I2C) bus the MPU-6500 already uses - it
// never calls Wire.begin() and never changes the bus clock. No third-party
// library is needed.
//
// Configured for infrared heart-rate sensing: SpO2 (red + IR) mode so the FIFO
// carries an IR slot, 100 samples/s averaged by 2 = 50 samples/s delivered,
// 18-bit resolution, 4096 nA ADC range. safeher_heart_rate.h assumes exactly
// this rate.
//
// Every function tolerates the sensor being absent or misbehaving: begin()
// simply returns false, and reads return an error code. Nothing here blocks
// for more than a few milliseconds or can halt the sketch.

#pragma once

#include <Wire.h>
#include <stdint.h>

namespace SafeHer {
namespace Max30102 {

constexpr uint8_t kAddress = 0x57;
constexpr uint8_t kExpectedPartId = 0x15;

// LED pulse amplitude, 0x00..0xFF (about 0..50 mA). Raise it if the finger
// reading is weak, lower it if the raw IR value saturates (262143).
constexpr uint8_t kLedPulseAmplitude = 0x1F;

namespace Reg {
constexpr uint8_t kFifoWritePtr = 0x04;
constexpr uint8_t kFifoOverflow = 0x05;
constexpr uint8_t kFifoReadPtr = 0x06;
constexpr uint8_t kFifoData = 0x07;
constexpr uint8_t kFifoConfig = 0x08;
constexpr uint8_t kModeConfig = 0x09;
constexpr uint8_t kSpo2Config = 0x0A;
constexpr uint8_t kLed1PulseAmp = 0x0C;  // red
constexpr uint8_t kLed2PulseAmp = 0x0D;  // infrared
constexpr uint8_t kPartId = 0xFF;
}  // namespace Reg

// One FIFO sample in SpO2 mode is 6 bytes: 3 red, then 3 infrared.
constexpr int kBytesPerSample = 6;
// Samples fetched per I2C transaction. 10 * 6 = 60 bytes, comfortably inside
// the ESP32 Wire buffer (128 bytes).
constexpr int kSamplesPerRead = 10;

inline bool writeRegister(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(kAddress);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

inline bool readRegister(uint8_t reg, uint8_t& value) {
  Wire.beginTransmission(kAddress);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom((int)kAddress, 1) != 1) return false;
  value = Wire.read();
  return true;
}

// Detects and configures the sensor. Returns false if it is not there (wrong
// part ID or no ACK), in which case the rest of the sketch carries on without
// heart rate.
inline bool begin() {
  uint8_t partId = 0;
  if (!readRegister(Reg::kPartId, partId) || partId != kExpectedPartId) {
    return false;
  }

  // Soft reset; the RESET bit clears itself when done.
  if (!writeRegister(Reg::kModeConfig, 0x40)) return false;
  for (int i = 0; i < 100; ++i) {
    uint8_t mode = 0;
    if (readRegister(Reg::kModeConfig, mode) && (mode & 0x40) == 0) break;
    delay(1);
  }

  bool ok = true;
  // Sample averaging 2, FIFO rollover on, almost-full 15.
  ok &= writeRegister(Reg::kFifoConfig, 0x20 | 0x10 | 0x0F);
  // ADC range 4096 nA, 100 samples/s, 411 us pulse width (18-bit).
  ok &= writeRegister(Reg::kSpo2Config, 0x20 | 0x04 | 0x03);
  ok &= writeRegister(Reg::kLed1PulseAmp, kLedPulseAmplitude);
  ok &= writeRegister(Reg::kLed2PulseAmp, kLedPulseAmplitude);
  // Clear FIFO pointers, then start in SpO2 (red + IR) mode.
  ok &= writeRegister(Reg::kFifoWritePtr, 0x00);
  ok &= writeRegister(Reg::kFifoOverflow, 0x00);
  ok &= writeRegister(Reg::kFifoReadPtr, 0x00);
  ok &= writeRegister(Reg::kModeConfig, 0x03);
  return ok;
}

// Reads the infrared value of every sample currently in the FIFO, up to
// `maxSamples`, into `ir`. `lost` is set to the number of samples the sensor
// dropped because the FIFO overflowed before it was read.
//
// Returns the number of samples read (0 if none are waiting), or -1 if the
// sensor did not respond.
inline int readIrSamples(uint32_t* ir, int maxSamples, int& lost) {
  lost = 0;
  uint8_t writePtr = 0, overflow = 0, readPtr = 0;
  if (!readRegister(Reg::kFifoWritePtr, writePtr) ||
      !readRegister(Reg::kFifoOverflow, overflow) ||
      !readRegister(Reg::kFifoReadPtr, readPtr)) {
    return -1;
  }
  writePtr &= 0x1F;
  overflow &= 0x1F;
  readPtr &= 0x1F;

  int available = (writePtr - readPtr) & 0x1F;
  if (overflow > 0) {
    lost = overflow;
    available = 32;  // the FIFO was full
  }

  int count = 0;
  while (available > 0 && count < maxSamples) {
    int chunk = available;
    if (chunk > kSamplesPerRead) chunk = kSamplesPerRead;
    if (chunk > maxSamples - count) chunk = maxSamples - count;
    const int bytes = chunk * kBytesPerSample;

    Wire.beginTransmission(kAddress);
    Wire.write(Reg::kFifoData);
    if (Wire.endTransmission(false) != 0) return count > 0 ? count : -1;
    if (Wire.requestFrom((int)kAddress, bytes) != bytes) return count > 0 ? count : -1;

    for (int i = 0; i < chunk; ++i) {
      Wire.read();  // red, unused: 3 bytes
      Wire.read();
      Wire.read();
      const uint32_t b0 = Wire.read();
      const uint32_t b1 = Wire.read();
      const uint32_t b2 = Wire.read();
      ir[count++] = ((b0 << 16) | (b1 << 8) | b2) & 0x3FFFF;  // 18-bit
    }
    available -= chunk;
  }
  return count;
}

}  // namespace Max30102
}  // namespace SafeHer
