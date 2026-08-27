#!/usr/bin/env python3
"""SafeHer Real-Time Inference from ESP32-C3 Serial Stream (7-Class Model V5).

This script reads raw sensor data from an ESP32-C3 over COM3 (100 Hz),
creates sliding windows (100 samples @ 100 Hz = 1 second), computes features,
runs the V5 7-class XGBoost model, and continuously outputs:

    SAFE / ABNORMAL / HIGH_RISK

with class prediction, confidence, and reasoning.

NO MODELS ARE RETRAINED OR MODIFIED.
This is real-time inference only using the V5 7-class glove model.

Expected serial format from ESP32:
    timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz (comma-separated, no header)
    Example: 34242,-2248,-316,15796,-250,456,36
    
Feature window: 100 samples per window (1 second @ 100 Hz)
Window step: 50 samples (50% overlap → ~2 Hz output frequency)
Output: One prediction every 0.5 seconds

Usage:
    python safeher_realtime_inference.py --com COM3 --baudrate 115200
"""

from __future__ import annotations

import argparse
import json
import queue
import sys
import threading
import time
from collections import deque
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd
import serial
from xgboost import XGBClassifier

# ============================================================================
# CONFIGURATION
# ============================================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Model paths (7-CLASS GLOVE MODEL V5 ONLY)
GLOVE_7CLASS_MODEL_PATH = PROJECT_ROOT / "models" / "glove_7class" / "safeher_glove_7class_v5_xgboost.json"
GLOVE_7CLASS_FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class" / "glove_7class_v5_feature_columns.json"
GLOVE_7CLASS_LABEL_MAPPING_PATH = PROJECT_ROOT / "models" / "glove_7class" / "glove_7class_v5_label_mapping.json"

# Sampling parameters (100 Hz from actual ESP32-C3 sensor stream)
SAMPLING_RATE_HZ = 100  # Actual sensor stream rate
WINDOW_SIZE_SAMPLES = 100  # 1 second @ 100 Hz
STEP_SIZE_SAMPLES = 50  # 50% overlap

# Confidence thresholds
FALL_HIGH_RISK_THRESHOLD = 0.65  # FALL class needs >= 0.65 confidence to be HIGH_RISK

# Safety states
SAFE = "SAFE"
ABNORMAL = "ABNORMAL"
HIGH_RISK = "HIGH_RISK"

# 7-class labels (must match training order)
CLASS_LABELS = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]

# Sensor columns expected from ESP32
SENSOR_COLUMNS = ["Ax", "Ay", "Az", "Gx", "Gy", "Gz"]


# ============================================================================
# MODEL LOADING
# ============================================================================

def load_model() -> XGBClassifier:
    """Load the 7-class XGBoost model."""
    if not GLOVE_7CLASS_MODEL_PATH.exists():
        raise FileNotFoundError(f"7-class model not found: {GLOVE_7CLASS_MODEL_PATH}")

    print("[INIT] Loading 7-class glove model...")
    model = XGBClassifier()
    model.load_model(str(GLOVE_7CLASS_MODEL_PATH))

    return model


def load_feature_columns() -> List[str]:
    """Load feature column definitions for the 7-class model."""
    print("[INIT] Loading feature columns...")
    with open(GLOVE_7CLASS_FEATURE_COLUMNS_PATH, "r") as f:
        features = json.load(f)

    print(f"[INIT] Model expects {len(features)} features")

    return features


def load_label_mapping() -> Dict[int, str]:
    """Load 7-class label to string mapping."""
    print("[INIT] Loading label mapping...")
    with open(GLOVE_7CLASS_LABEL_MAPPING_PATH, "r") as f:
        label_map = json.load(f)

    # Invert to int->str if needed (JSON keys are strings)
    if isinstance(list(label_map.keys())[0], str):
        return {int(v): k for k, v in label_map.items()}
    return label_map


# ============================================================================
# FEATURE EXTRACTION FOR REAL-TIME WINDOW
# ============================================================================

def compute_stats(values: np.ndarray) -> Dict[str, float]:
    """Compute statistics for a signal window."""
    if values.size == 0:
        return {
            "mean": 0.0,
            "std": 0.0,
            "min": 0.0,
            "max": 0.0,
            "range": 0.0,
            "rms": 0.0,
        }

    values = values.astype(float)
    return {
        "mean": float(np.mean(values)),
        "std": float(np.std(values, ddof=0)),
        "min": float(np.min(values)),
        "max": float(np.max(values)),
        "range": float(np.max(values) - np.min(values)),
        "rms": float(np.sqrt(np.mean(np.square(values)))),
    }


def extract_glove_7class_features(window_df: pd.DataFrame) -> Dict[str, float]:
    """Extract 51 features for 7-class glove movement classifier from 100-sample window.
    
    Features:
    - 6 sensors × 6 stats each = 36 features
    - acc_mag (acceleration magnitude) × 6 stats = 6 features
    - gyro_mag (gyro magnitude) × 6 stats = 6 features
    - jerk × 3 stats = 3 features
    Total: 51 features
    
    This MUST match the exact feature extraction used during training.
    """
    features = {}

    # Raw sensor signals (Ax, Ay, Az, Gx, Gy, Gz)
    for col in SENSOR_COLUMNS:
        stats = compute_stats(window_df[col].to_numpy())
        for stat_name, stat_value in stats.items():
            features[f"{col}_{stat_name}"] = stat_value

    # Acceleration magnitude
    ax = window_df["Ax"].to_numpy(dtype=float)
    ay = window_df["Ay"].to_numpy(dtype=float)
    az = window_df["Az"].to_numpy(dtype=float)
    
    acc_mag = np.sqrt(ax**2 + ay**2 + az**2)
    stats = compute_stats(acc_mag)
    for stat_name, stat_value in stats.items():
        features[f"acc_mag_{stat_name}"] = stat_value

    # Gyro magnitude
    gx = window_df["Gx"].to_numpy(dtype=float)
    gy = window_df["Gy"].to_numpy(dtype=float)
    gz = window_df["Gz"].to_numpy(dtype=float)
    
    gyro_mag = np.sqrt(gx**2 + gy**2 + gz**2)
    stats = compute_stats(gyro_mag)
    for stat_name, stat_value in stats.items():
        features[f"gyro_mag_{stat_name}"] = stat_value

    # Jerk (derivative of acceleration magnitude)
    jerk = np.diff(acc_mag)
    if jerk.size > 0:
        features["jerk_mean"] = float(np.mean(jerk))
        features["jerk_std"] = float(np.std(jerk, ddof=0))
        features["jerk_max"] = float(np.max(jerk))
    else:
        features["jerk_mean"] = 0.0
        features["jerk_std"] = 0.0
        features["jerk_max"] = 0.0

    return features


# ============================================================================
# SAFETY LOGIC
# ============================================================================

def apply_safety_logic(class_label: str, confidence: float) -> Tuple[str, str]:
    """Apply unified safety decision logic for the 7-class model.
    
    Mapping:
    - NORMAL (confidence any) → SAFE
    - JERK, PUSH, PULL, SHAKING, TWISTING → ABNORMAL
    - FALL with confidence < 0.65 → ABNORMAL (insufficient confidence)
    - FALL with confidence >= 0.65 → HIGH_RISK (strong fall signal)
    
    Returns:
        Tuple of (final_state, reason_string)
    """
    if class_label == "NORMAL":
        return SAFE, "Normal activity detected"
    
    if class_label == "FALL":
        if confidence >= FALL_HIGH_RISK_THRESHOLD:
            return HIGH_RISK, f"Fall detected with high confidence ({confidence:.3f})"
        else:
            return ABNORMAL, f"Fall detected but low confidence ({confidence:.3f})"
    
    # JERK, PUSH, PULL, SHAKING, TWISTING
    return ABNORMAL, f"Detected: {class_label}"


# ============================================================================
# REAL-TIME INFERENCE ENGINE
# ============================================================================

class RealtimeInferenceEngine:
    """Manages sliding window buffer and continuous inference."""

    def __init__(self, model, feature_columns, label_map):
        self.model = model
        self.feature_columns = feature_columns
        self.label_map = label_map

        # Sliding window buffer
        self.buffer = deque(maxlen=WINDOW_SIZE_SAMPLES)
        self.buffer_lock = threading.Lock()

        # Output counter
        self.prediction_count = 0
        self.samples_since_last_prediction = 0

        # Diagnostic counters
        self.valid_samples_received = 0
        self.invalid_lines_ignored = 0
        self.last_sample_time = None
        self.estimated_sample_rate = 0.0
        self.first_sample_timestamp = None
        self.last_valid_sample_time = time.time()

    def add_sample(self, sample: Dict[str, float], timestamp_ms: int = None) -> None:
        """Add a single sensor sample to the buffer and update diagnostics."""
        with self.buffer_lock:
            self.buffer.append(sample)
            self.valid_samples_received += 1
            self.samples_since_last_prediction += 1
            self.last_valid_sample_time = time.time()
            
            # Estimate sampling rate based on timestamps
            if timestamp_ms is not None:
                if self.first_sample_timestamp is None:
                    self.first_sample_timestamp = timestamp_ms
                    self.last_sample_time = timestamp_ms
                else:
                    time_delta_ms = timestamp_ms - self.last_sample_time
                    if time_delta_ms > 0:
                        # Exponential moving average for rate estimation
                        new_rate = 1000.0 / time_delta_ms
                        if self.estimated_sample_rate == 0.0:
                            self.estimated_sample_rate = new_rate
                        else:
                            self.estimated_sample_rate = 0.9 * self.estimated_sample_rate + 0.1 * new_rate
                    self.last_sample_time = timestamp_ms

    def get_window_df(self) -> pd.DataFrame | None:
        """Get current buffer as DataFrame if it's full."""
        with self.buffer_lock:
            buffer_size = len(self.buffer)
            if buffer_size < WINDOW_SIZE_SAMPLES:
                return None
            return pd.DataFrame(list(self.buffer))
    
    def get_diagnostics(self) -> Dict:
        """Get current diagnostic information."""
        with self.buffer_lock:
            return {
                "valid_samples": self.valid_samples_received,
                "invalid_lines": self.invalid_lines_ignored,
                "buffer_size": len(self.buffer),
                "estimated_rate_hz": self.estimated_sample_rate,
                "last_valid_time": self.last_valid_sample_time,
            }

    def predict_once(self) -> Dict | None:
        """Run inference on current window if ready."""
        window_df = self.get_window_df()
        if window_df is None:
            return None

        try:
            # Extract features for the 7-class model
            features_dict = extract_glove_7class_features(window_df)

            # Build feature vector in correct order
            X = np.array(
                [features_dict.get(feat, 0.0) for feat in self.feature_columns]
            ).reshape(1, -1)

            # Get predictions from 7-class model
            proba = self.model.predict_proba(X)[0]
            pred_idx = np.argmax(proba)
            pred_label = self.label_map[pred_idx]
            confidence = proba[pred_idx]

            # Apply safety logic
            final_state, reason = apply_safety_logic(pred_label, confidence)

            self.prediction_count += 1

            return {
                "timestamp": time.time(),
                "prediction_num": self.prediction_count,
                "final_state": final_state,
                "class": pred_label,
                "confidence": confidence,
                "reason": reason,
            }

        except Exception as e:
            print(f"[ERROR] Inference failed: {e}")
            return None


# ============================================================================
# SERIAL READER THREAD
# ============================================================================

def serial_reader(port: str, baudrate: int, engine: RealtimeInferenceEngine, stop_event: threading.Event):
    """Read sensor data from serial port continuously.
    
    Handles format: timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz
    Ignores: startup messages, blank lines, malformed lines, non-numeric lines
    """
    try:
        ser = serial.Serial(port, baudrate, timeout=1.0)
        print(f"[SERIAL] Connected to {port} @ {baudrate} baud")
        time.sleep(1)  # Wait for ESP32 to stabilize

        line_buffer = ""

        while not stop_event.is_set():
            try:
                # Read bytes from serial
                if ser.in_waiting > 0:
                    data = ser.read(ser.in_waiting).decode("utf-8", errors="ignore")
                    line_buffer += data

                    # Process complete lines
                    while "\n" in line_buffer:
                        line, line_buffer = line_buffer.split("\n", 1)
                        line = line.strip()

                        if not line:
                            # Blank line, skip
                            continue

                        # Parse CSV: timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz (7 values)
                        try:
                            parts = line.split(",")
                            if len(parts) != 7:
                                # Wrong number of values, likely Arduino startup message
                                with engine.buffer_lock:
                                    engine.invalid_lines_ignored += 1
                                continue

                            # Try to parse all values as numbers
                            values = [float(x) for x in parts]
                            timestamp_ms = int(values[0])

                            sample = {
                                "Ax": values[1],
                                "Ay": values[2],
                                "Az": values[3],
                                "Gx": values[4],
                                "Gy": values[5],
                                "Gz": values[6],
                            }

                            engine.add_sample(sample, timestamp_ms=timestamp_ms)

                            # Print progress every 100 samples (1 window)
                            diag = engine.get_diagnostics()
                            if diag["valid_samples"] % WINDOW_SIZE_SAMPLES == 0:
                                print(
                                    f"[DATA] Received {diag['valid_samples']} samples | "
                                    f"Est. rate: {diag['estimated_rate_hz']:.1f} Hz | "
                                    f"Buffer: {diag['buffer_size']}/{WINDOW_SIZE_SAMPLES}",
                                    end="\r"
                                )

                        except (ValueError, IndexError):
                            # Malformed line (non-numeric), skip silently
                            with engine.buffer_lock:
                                engine.invalid_lines_ignored += 1
                            continue

            except (serial.SerialException, UnicodeDecodeError):
                # Serial error, but keep connection open and retry
                time.sleep(0.1)
                continue

        ser.close()
        print(f"\n[SERIAL] Connection closed")

    except serial.SerialException as e:
        print(f"[SERIAL] Failed to open {port}: {e}")


# ============================================================================
# MAIN LOOP
# ============================================================================

def main(args):
    """Main real-time inference loop."""
    print("=" * 80)
    print("SafeHer Real-Time Inference (7-Class Glove Model V5, ESP32-C3 @ 100 Hz)")
    print("=" * 80)
    print()

    # Load models and features
    try:
        model = load_model()
        feature_columns = load_feature_columns()
        label_map = load_label_mapping()
    except Exception as e:
        print(f"[ERROR] Failed to load model: {e}")
        return

    print()
    print("[INIT] Configuration:")
    print(f"  Model path: {GLOVE_7CLASS_MODEL_PATH}")
    print(f"  Model: 7-class glove XGBoost (V5)")
    print(f"  Serial port: {args.com}")
    print(f"  Baud rate: {args.baudrate}")
    print(f"  Window size: {WINDOW_SIZE_SAMPLES} samples (1.0 sec @ 100 Hz)")
    print(f"  Step size: {STEP_SIZE_SAMPLES} samples (50% overlap)")
    print(f"  Output frequency: ~2 Hz")
    print(f"  FALL HIGH_RISK threshold: {FALL_HIGH_RISK_THRESHOLD}")
    print(f"  Classes: {', '.join(CLASS_LABELS)}")
    print(f"  Timestamp format: timestamp_ms,Ax,Ay,Az,Gx,Gy,Gz")
    print()
    print("[READY] Waiting for serial data...")
    print()

    # Initialize inference engine
    engine = RealtimeInferenceEngine(model, feature_columns, label_map)

    # Start serial reader thread
    stop_event = threading.Event()
    reader_thread = threading.Thread(
        target=serial_reader,
        args=(args.com, args.baudrate, engine, stop_event),
        daemon=True,
    )
    reader_thread.start()

    # Main inference loop
    last_output_time = time.time()
    diagnostics_printed = False
    last_warning_check = time.time()

    try:
        while True:
            # Check buffer and scheduling state atomically to avoid races with the reader thread
            with engine.buffer_lock:
                buffer_size = len(engine.buffer)
                samples_since_last_prediction = engine.samples_since_last_prediction
                prediction_count = engine.prediction_count

            diag = engine.get_diagnostics()
            now = time.time()

            # Print initial diagnostics when first samples arrive
            if diag["valid_samples"] >= WINDOW_SIZE_SAMPLES and not diagnostics_printed:
                print(f"[DATA] Received {diag['valid_samples']} samples")
                print(f"[DATA] Estimated sampling rate: {diag['estimated_rate_hz']:.1f} Hz")
                print(f"[DATA] Starting inference loop...")
                print()
                diagnostics_printed = True

            # Warning if no valid samples for 3 seconds
            if now - last_warning_check >= 1.0:  # Check every 1 second
                time_since_last_sample = now - diag["last_valid_time"]
                if time_since_last_sample >= 3.0 and diag["valid_samples"] > 0:
                    print(f"[WARNING] No valid sensor samples received for {time_since_last_sample:.1f} seconds")
                last_warning_check = now

            # Diagnostic output every 1000 samples
            if diag["valid_samples"] > 0 and diag["valid_samples"] % 1000 == 0:
                print(
                    f"[DATA] Received {diag['valid_samples']} samples | "
                    f"Est. rate: {diag['estimated_rate_hz']:.1f} Hz | "
                    f"Buffer: {diag['buffer_size']}/{WINDOW_SIZE_SAMPLES} | "
                    f"Predictions: {prediction_count}"
                )

            # Trigger a prediction when the window is full and enough new samples have arrived
            # since the last prediction. Because the deque is capped at 100 samples, we must
            # rely on a separate counter rather than buffer length growth.
            should_predict = (
                buffer_size >= WINDOW_SIZE_SAMPLES
                and (
                    prediction_count == 0
                    or samples_since_last_prediction >= STEP_SIZE_SAMPLES
                )
            )

            if should_predict:
                prediction = engine.predict_once()

                if prediction:
                    print(
                        f"[{prediction['prediction_num']:04d}] "
                        f"{prediction['final_state']:10s} | "
                        f"Class: {prediction['class']:10s} | "
                        f"Confidence: {prediction['confidence']:.2f}"
                    )

                    with engine.buffer_lock:
                        engine.samples_since_last_prediction = 0

                    last_output_time = now

            # Small sleep to avoid busy-waiting
            time.sleep(0.01)

    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Stopping...")
        stop_event.set()
        reader_thread.join(timeout=2.0)
        print("[SHUTDOWN] Complete")


# ============================================================================
# ENTRY POINT
# ============================================================================

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="SafeHer Real-Time Inference (7-Class Glove Model) from ESP32-C3 Serial Stream"
    )
    parser.add_argument(
        "--com",
        type=str,
        default="COM3",
        help="Serial port (default: COM3)",
    )
    parser.add_argument(
        "--baudrate",
        type=int,
        default=115200,
        help="Serial baud rate (default: 115200)",
    )
    parser.add_argument(
        "--fall-threshold",
        type=float,
        default=0.65,
        help="Confidence threshold for FALL to be classified as HIGH_RISK (default: 0.65)",
    )

    args = parser.parse_args()
    
    # Update global threshold if provided
    if args.fall_threshold != 0.65:
        FALL_HIGH_RISK_THRESHOLD = args.fall_threshold
        print(f"[INIT] FALL threshold overridden: {FALL_HIGH_RISK_THRESHOLD}")

    main(args)
