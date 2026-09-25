// SafeHer glove - heart-rate estimator (MAX30102 IR signal -> BPM).
//
// Pure C++ with no Arduino dependencies, so the logic can be exercised off
// the device. The sketch feeds it one infrared sample at a fixed rate and
// reads the result with bpm().
//
// STUDENT PROTOTYPE - NOT A MEDICAL DEVICE. The value is an estimate from an
// optical pulse signal, sensitive to finger pressure, ambient light and
// movement. It must not be presented as medically accurate.
//
// What it guarantees:
//   * bpm() returns 0 ("unavailable") unless several consecutive beat
//     intervals have been measured and nearly all of them agree. It never
//     invents a value: a finger-level signal with no real pulse (noise only)
//     produces 0, not a plausible-looking number.
//   * A valid BPM is held while beats keep arriving and through a short
//     signal dropout, then cleared: after kNoFingerClearSamples without a
//     finger, or kNoBeatClearSamples without a newly validated beat.
//   * Every threshold below is a tunable. They assume the sensor is set up as
//     in safeher_max30102.h (50 samples/s of 18-bit IR) and were chosen against
//     synthetic pulse signals, NOT against a real finger. Expect to retune
//     kFingerIrThreshold and kMinPulseAmplitude on the actual glove.
//
// Method: two cascaded ~0.5 Hz high-pass stages remove the DC level and slow
// baseline drift, a ~4 Hz low-pass removes noise, and local peaks above an
// adaptive fraction of the recent peak height are treated as beats. The
// interval between consecutive peaks gives the heart rate; the median of
// recent intervals is used, and an estimate is only published when nearly all
// recent intervals agree with it AND the filtered signal repeats at that
// period (autocorrelation), which noise does not.

#pragma once

#include <math.h>
#include <stdint.h>

namespace SafeHer {
namespace HeartRate {

// Samples per second delivered to addSample(). Must match the sensor setup.
constexpr float kSampleRateHz = 50.0f;

// Raw IR level (18-bit counts) above which a finger is assumed present. With
// no finger the reading is ambient only and far lower. Tune per LED current.
constexpr uint32_t kFingerIrThreshold = 20000;

// Samples to wait after a finger appears before trusting the signal (filters
// settle and the first pressure transient passes).
constexpr int kSettleSamples = 50;  // 1 s

// A finger absent this long clears the BPM. Shorter lifts are ridden out.
constexpr int kNoFingerClearSamples = 250;  // 5 s

// This long without a newly validated beat (finger present) clears the BPM.
// While the finger stays on, the last validated BPM is held through weak or
// noisy stretches this long, so the display does not flicker to "--" on every
// brief bad moment. Past it the value is treated as stale and cleared.
constexpr int kNoBeatClearSamples = 1000;  // 20 s

// Smallest filtered pulse amplitude (counts) treated as a real beat.
constexpr float kMinPulseAmplitude = 50.0f;

// A peak must reach this fraction of the recent peak height.
constexpr float kPeakFraction = 0.5f;

// Plausible beat spacing: ~33..166 bpm.
constexpr int kMinBeatSamples = 18;  // 0.36 s
constexpr int kMaxBeatSamples = 90;  // 1.80 s

// Intervals kept, and how many are needed before a BPM is published.
constexpr int kIntervalHistory = 6;
constexpr int kMinIntervalsForBpm = 4;

// An interval "agrees" if it is within this fraction of the median. All but
// at most one of the recent intervals must agree.
constexpr float kIntervalTolerance = 0.20f;

// Published range.
constexpr int kMinBpm = 40;
constexpr int kMaxBpm = 180;

// Signal-quality gate. Beat intervals that merely agree are not enough: noise
// with peaks in it can agree by chance. A real pulse also repeats, so the
// filtered signal must correlate with itself one beat later. Measured on
// synthetic data: real pulses score a median 0.85-0.99, pure noise ~0.02.
//
// It is checked one beat back (>= kMinPeriodicity) AND two beats back (>=
// kMinPeriodicityTwoBeats). The second check is what stops a pulse weaker than
// the noise from being reported as a plausible number.
constexpr float kMinPeriodicity = 0.7f;
constexpr float kMinPeriodicityTwoBeats = 0.5f;
constexpr int kCorrelationWindow = 100;  // 2 s of filtered signal
constexpr int kSignalRing = 320;         // must exceed window + 2 * longest beat

// Filter coefficients at 50 samples/s.
constexpr float kHighPassAlpha = 0.06f;  // ~0.5 Hz, applied twice
constexpr float kLowPassAlpha = 0.40f;   // ~4 Hz
constexpr float kEnvDecay = 0.995f;      // peak-height memory, ~3 s half-life

class HeartRateEstimator {
 public:
  HeartRateEstimator() { reset(); }

  // Forget everything (finger removed for good, or sensor re-initialised).
  void reset() {
    bpm_ = 0;
    fingerLostSamples_ = 0;
    clearSignal();
    clearIntervals();
    lastBeatSample_ = 0;
  }

  // Account for samples the sensor produced but the caller never saw (FIFO
  // overflow), so beat timing stays correct across the gap.
  void skip(int samples) {
    if (samples > 0) sampleIndex_ += (uint32_t)samples;
  }

  // Feed one raw infrared sample.
  void addSample(uint32_t ir) {
    ++sampleIndex_;

    if (ir < kFingerIrThreshold) {
      primed_ = false;  // baseline is stale once the finger has moved
      settle_ = 0;
      if (++fingerLostSamples_ >= kNoFingerClearSamples) {
        reset();
      }
      return;
    }
    fingerLostSamples_ = 0;

    const float x = (float)ir;
    if (!primed_) {
      // Finger (re)appeared: start the filters from the current level.
      dc_ = x;
      dc2_ = 0.0f;
      lp_ = 0.0f;
      prev1_ = 0.0f;
      prev2_ = 0.0f;
      env_ = 0.0f;
      settle_ = 0;
      lastPeakSample_ = 0;
      ringCount_ = 0;
      clearIntervals();  // intervals across a dropout are not comparable
      primed_ = true;
      return;
    }

    dc_ += kHighPassAlpha * (x - dc_);
    const float highPass1 = x - dc_;
    dc2_ += kHighPassAlpha * (highPass1 - dc2_);
    lp_ += kLowPassAlpha * ((highPass1 - dc2_) - lp_);
    env_ = fmaxf(lp_, env_ * kEnvDecay);
    ring_[ringHead_] = lp_;
    ringHead_ = (ringHead_ + 1) % kSignalRing;
    if (ringCount_ < kSignalRing) ++ringCount_;

    if (settle_ < kSettleSamples) {
      ++settle_;
      prev2_ = prev1_;
      prev1_ = lp_;
      return;
    }

    // prev1_ is a local maximum if it rose from prev2_ and does not exceed
    // the newest sample.
    if (prev1_ > prev2_ && prev1_ >= lp_ && prev1_ > kMinPulseAmplitude &&
        prev1_ > kPeakFraction * env_) {
      onPeak(sampleIndex_ - 1);
    }
    prev2_ = prev1_;
    prev1_ = lp_;

    if (bpm_ > 0 && (sampleIndex_ - lastBeatSample_) > (uint32_t)kNoBeatClearSamples) {
      bpm_ = 0;
      clearIntervals();
    }
  }

  // Latest valid heart rate in beats per minute, or 0 if none.
  int bpm() const { return bpm_; }

  // True while a finger-level signal is present.
  bool fingerPresent() const { return primed_; }

  // Number of intervals currently held (for diagnostics).
  int intervalCount() const { return intervalCount_; }

 private:
  void clearSignal() {
    primed_ = false;
    settle_ = 0;
    dc_ = 0.0f;
    dc2_ = 0.0f;
    lp_ = 0.0f;
    prev1_ = 0.0f;
    prev2_ = 0.0f;
    env_ = 0.0f;
    lastPeakSample_ = 0;
  }

  void clearIntervals() {
    intervalCount_ = 0;
    intervalNext_ = 0;
  }

  // Normalized correlation of the newest kCorrelationWindow filtered samples
  // with the same signal `lag` samples earlier. ~1 for a repeating pulse,
  // ~0 for noise. Returns 0 if there is not enough history yet.
  float periodicity(int lag) const {
    if (lag <= 0 || ringCount_ < kCorrelationWindow + lag) return 0.0f;
    float num = 0.0f, energyA = 0.0f, energyB = 0.0f;
    for (int k = 0; k < kCorrelationWindow; ++k) {
      const float a = ring_[(ringHead_ - 1 - k + 2 * kSignalRing) % kSignalRing];
      const float b = ring_[(ringHead_ - 1 - k - lag + 2 * kSignalRing) % kSignalRing];
      num += a * b;
      energyA += a * a;
      energyB += b * b;
    }
    if (energyA <= 0.0f || energyB <= 0.0f) return 0.0f;
    return num / sqrtf(energyA * energyB);
  }

  static float median(const int* values, int count) {
    int sorted[kIntervalHistory];
    for (int i = 0; i < count; ++i) sorted[i] = values[i];
    for (int i = 1; i < count; ++i) {
      const int v = sorted[i];
      int j = i - 1;
      while (j >= 0 && sorted[j] > v) {
        sorted[j + 1] = sorted[j];
        --j;
      }
      sorted[j + 1] = v;
    }
    return (count % 2) ? (float)sorted[count / 2]
                       : 0.5f * (float)(sorted[count / 2 - 1] + sorted[count / 2]);
  }

  void onPeak(uint32_t peakSample) {
    if (lastPeakSample_ == 0) {
      lastPeakSample_ = peakSample;  // first peak: only a reference point
      return;
    }
    const int interval = (int)(peakSample - lastPeakSample_);
    if (interval < kMinBeatSamples) return;  // ripple of the same beat

    lastPeakSample_ = peakSample;
    if (interval > kMaxBeatSamples) {
      clearIntervals();  // beats were missed: start a new run
      return;
    }

    intervals_[intervalNext_] = interval;
    intervalNext_ = (intervalNext_ + 1) % kIntervalHistory;
    if (intervalCount_ < kIntervalHistory) ++intervalCount_;
    if (intervalCount_ < kMinIntervalsForBpm) return;

    // Publish only if nearly all recent intervals agree with their median: a
    // real pulse is regular, noise that happens to have peaks is not.
    const float med = median(intervals_, intervalCount_);
    int agreeing = 0;
    float sum = 0.0f;
    for (int i = 0; i < intervalCount_; ++i) {
      if (fabsf((float)intervals_[i] - med) <= kIntervalTolerance * med) {
        ++agreeing;
        sum += (float)intervals_[i];
      }
    }
    if (agreeing < intervalCount_ - 1) return;

    const int estimate = (int)lroundf(60.0f * kSampleRateHz * (float)agreeing / sum);
    if (estimate < kMinBpm || estimate > kMaxBpm) return;
    const int lag = (int)lroundf(sum / (float)agreeing);
    if (periodicity(lag) >= kMinPeriodicity &&
        periodicity(2 * lag) >= kMinPeriodicityTwoBeats) {
      bpm_ = estimate;
      lastBeatSample_ = sampleIndex_;
    }
  }

  int bpm_ = 0;
  uint32_t sampleIndex_ = 0;
  uint32_t lastBeatSample_ = 0;
  uint32_t lastPeakSample_ = 0;
  int fingerLostSamples_ = 0;
  int settle_ = 0;
  bool primed_ = false;
  float dc_ = 0.0f;
  float dc2_ = 0.0f;
  float lp_ = 0.0f;
  float prev1_ = 0.0f;
  float prev2_ = 0.0f;
  float env_ = 0.0f;
  int intervals_[kIntervalHistory] = {0};
  int intervalCount_ = 0;
  int intervalNext_ = 0;
  float ring_[kSignalRing] = {0.0f};
  int ringHead_ = 0;
  int ringCount_ = 0;
};

}  // namespace HeartRate
}  // namespace SafeHer
