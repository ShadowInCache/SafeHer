#!/usr/bin/env python3
"""Collect labeled glove sensor data from the SafeHer ESP32-C3 + MPU-6500 stream."""

from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from pathlib import Path

import serial

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
CONFIGURED_RATE_HZ = 100

LABELS = {
    1: "NORMAL",
    2: "JERK",
    3: "PUSH",
    4: "PULL",
    5: "SHAKING",
    6: "TWISTING",
    7: "FALL",
}

ACTIVITY_INSTRUCTIONS = {
    "NORMAL": "Perform normal everyday hand movements. Do not intentionally create sudden movements.",
    "JERK": "Perform a short, sudden hand jerk. Repeat naturally with rest between repetitions.",
    "PUSH": "Perform controlled push-like hand movements. Do not use excessive force.",
    "PULL": "Perform controlled pull-like hand movements. Do not use excessive force.",
    "SHAKING": "Shake the hand/glove naturally for short periods.",
    "TWISTING": "Rotate/twist the wrist naturally.",
    "FALL": (
        "Use only safe, controlled fall-like arm/hand motion. Examples: sudden downward movement, "
        "sudden forward movement, sudden sideways movement, sudden movement followed by a brief stop, "
        "or a stumble-like arm movement. Do not actually fall or hit the floor."
    ),
}


def list_serial_ports():
    try:
        from serial.tools import list_ports
        return [port.device for port in list_ports.comports()]
    except Exception:
        return []


def resolve_serial_port(requested: str | None) -> str:
    if requested:
        return requested

    ports = list_serial_ports()
    if "COM3" in ports:
        return "COM3"

    if ports:
        return ports[0]

    return "COM3"


def get_next_file_path(label: str) -> Path:
    folder = DATASET_DIR / label.lower()
    folder.mkdir(parents=True, exist_ok=True)

    existing = sorted(folder.glob(f"{label.lower()}_*.csv"))
    next_index = 1
    if existing:
        last = existing[-1].name
        stem = last.rsplit(".", 1)[0]
        try:
            next_index = int(stem.split("_")[-1]) + 1
        except ValueError:
            next_index = len(existing) + 1

    return folder / f"{label.lower()}_{next_index:03d}.csv"


def print_activity_menu() -> int:
    print("Select activity:")
    for key, value in LABELS.items():
        print(f"{key}. {value}")

    while True:
        choice = input("Enter selection (1-7): ").strip()
        if choice.isdigit() and int(choice) in LABELS:
            return int(choice)
        print("Invalid selection. Please enter a number from 1 to 7.")


def get_duration_seconds() -> float:
    default_value = "10"
    raw = input(f"Enter recording duration in seconds [{default_value}]: ").strip()
    if raw == "":
        return float(default_value)

    try:
        value = float(raw)
        if value <= 0:
            raise ValueError
        return value
    except ValueError:
        print("Invalid duration. Defaulting to 10 seconds.")
        return 10.0


def print_instructions(label: str) -> None:
    print(f"\nRecording label: {label}")
    print(ACTIVITY_INSTRUCTIONS[label])
    print("Keep the glove steady between repetitions and avoid excessive force.")
    print("The script will start collecting sensor data when the sensor stream is active.")


def should_ignore_line(line: str) -> bool:
    text = line.strip()
    if not text:
        return True
    lowered = text.lower()
    if lowered.startswith("mpu-") or "detected" in lowered:
        return True
    if lowered.startswith("who_am_i"):
        return True
    if lowered.startswith("timestamp_ms"):
        return True
    if lowered.startswith("error:") or lowered.startswith("debug:"):
        return True
    if lowered.startswith("raw:") or lowered.startswith("safety:"):
        return True
    if lowered.startswith("inference time:") or lowered.startswith("free heap"):
        return True
    if lowered.startswith("ble:") or lowered.startswith("temp_sensor_diagnostic"):
        return True
    return False


def parse_sensor_row(line: str):
    values = [value.strip() for value in line.split(",")]
    if len(values) != 7:
        return None

    try:
        row = [int(value) for value in values]
    except ValueError:
        return None

    timestamp_ms, *sensor_values = row
    if timestamp_ms < 0 or any(value < -32768 or value > 32767 for value in sensor_values):
        return None
    return row


def approximate_sampling_rate(timestamps_ms):
    if len(timestamps_ms) < 2:
        return 0.0

    dt_ms = timestamps_ms[-1] - timestamps_ms[0]
    if dt_ms <= 0:
        return 0.0

    samples = len(timestamps_ms) - 1
    dt_seconds = dt_ms / 1000.0
    return samples / dt_seconds if dt_seconds > 0 else 0.0


def print_summary(file_path: Path, label: str, rows, duration_sec: float):
    timestamps = [int(row[0]) for row in rows]
    sample_count = len(rows)
    rate_hz = approximate_sampling_rate(timestamps)

    print("\nRecording complete.")
    print(f"File path: {file_path}")
    print(f"Label: {label}")
    print(f"Number of samples: {sample_count}")
    print(f"Recording duration: {duration_sec:.2f} s")
    print(f"Approximate sampling rate: {rate_hz:.2f} Hz")

    if abs(rate_hz - CONFIGURED_RATE_HZ) > 10:
        print(f"Warning: sampling rate is significantly different from the configured {CONFIGURED_RATE_HZ} Hz.")

    print("First 3 rows:")
    for row in rows[:3]:
        print(",".join(str(value) for value in row))

    print("Last 3 rows:")
    for row in rows[-3:]:
        print(",".join(str(value) for value in row))


def record_activity(label: str, duration_seconds: float, port: str, baudrate: int) -> Path:
    output_path = get_next_file_path(label)
    rows = []
    rejected_lines = 0
    start_time = time.time()
    timeout_seconds = duration_seconds + 2

    print(f"\nOpening serial port {port} at {baudrate} baud...")
    try:
        ser = serial.Serial(port, baudrate, timeout=1)
    except serial.SerialException as exc:
        available_ports = list_serial_ports()
        available_text = ", ".join(available_ports) if available_ports else "none detected"
        raise RuntimeError(
            f"Could not open {port}: {exc}. Available serial ports: {available_text}. "
            "Reconnect the ESP32-C3 or use the detected port with --port."
        ) from exc
    time.sleep(1.5)
    ser.reset_input_buffer()
    start_time = time.time()

    try:
        while (time.time() - start_time) < duration_seconds:
            if ser.in_waiting > 0:
                raw_line = ser.readline()
                if not raw_line:
                    continue
                line = raw_line.decode("utf-8", errors="ignore").strip()
                if should_ignore_line(line):
                    continue

                parsed = parse_sensor_row(line)
                if parsed is None:
                    rejected_lines += 1
                    continue

                rows.append(parsed)

        if not rows:
            raise RuntimeError(
                "No valid sensor samples were received during the recording window "
                f"({rejected_lines} non-data/malformed lines rejected). "
                "Confirm DATA_COLLECTION_MODE is 1 and upload the collection sketch."
            )

        with output_path.open("w", newline="") as csv_file:
            writer = csv.writer(csv_file)
            writer.writerow(["timestamp_ms", "Ax", "Ay", "Az", "Gx", "Gy", "Gz", "label"])
            for row in rows:
                writer.writerow([*row, label])

        print_summary(output_path, label, rows, duration_seconds)
        print(f"Rejected non-data/malformed lines: {rejected_lines}")
        return output_path

    finally:
        ser.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect SafeHer glove IMU dataset from the ESP32-C3 stream.")
    parser.add_argument("--port", default=None, help="Serial port (default: auto-detect COM3 or first available port)")
    parser.add_argument("--baud", type=int, default=115200, help="Serial baud rate (default: 115200)")
    args = parser.parse_args()

    port = resolve_serial_port(args.port)
    choice = print_activity_menu()
    label = LABELS[choice]
    print_instructions(label)
    duration = get_duration_seconds()

    try:
        output_path = record_activity(label, duration, port, args.baud)
        print(f"\nSaved CSV file: {output_path}")
    except Exception as exc:  # pragma: no cover - user-facing CLI error path
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
