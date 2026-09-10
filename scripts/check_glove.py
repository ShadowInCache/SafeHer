"""Check a SafeHer glove over BLE, before the app is involved.

    pip install bleak
    python scripts/check_glove.py
    python scripts/check_glove.py --seconds 60      # long enough to act out a fall

## Why check the firmware separately from the app

Pairing in the app answers one question — did it work — and when the answer is
no, the fault could be the advertisement, the service UUID, the characteristic,
the payload format, or the app. This exercises the same contract the phone does,
in the same order, and names the step that failed.

It also decodes what the glove is actually saying. A glove that connects but
notifies `FALL,0.93` while you sit still is a different problem from one that
never notifies at all, and only the payload tells you which you have.
"""

from __future__ import annotations

import argparse
import asyncio
from collections import Counter

DEVICE_NAME = "SafeHer-Glove"
SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
CLASSIFICATION_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
TELEMETRY_UUID = "33b4fb00-9c17-4ad2-8fc9-89ad6dbc76bd"

KNOWN_LABELS = {"NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"}

# The app's rule, from GloveThreatDetector.
REQUIRED_HITS = 2
WINDOW_SECONDS = 5.0
THRESHOLD = 0.75

PASS, FAIL, WARN = "PASS", "FAIL", "WARN"
results: list[tuple[str, str]] = []


def record(status: str, name: str, detail: str = "") -> None:
    results.append((status, name))
    mark = {"PASS": "  ok  ", "FAIL": " FAIL ", "WARN": " warn "}[status]
    print(f"[{mark}] {name}" + (f" — {detail}" if detail else ""), flush=True)


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=float, default=30.0)
    parser.add_argument("--address", help="skip the scan and connect directly")
    args = parser.parse_args()

    try:
        from bleak import BleakClient, BleakScanner
    except ImportError:
        raise SystemExit("pip install bleak")

    print(f"\nChecking glove over BLE\n" + "-" * 62)

    address = args.address
    if not address:
        print(f"scanning for {DEVICE_NAME}…", flush=True)
        devices = await BleakScanner.discover(timeout=10.0)
        match = next((d for d in devices if (d.name or "") == DEVICE_NAME), None)
        if match is None:
            names = ", ".join(sorted({d.name for d in devices if d.name})[:8]) or "nothing"
            record(FAIL, f"advertising as {DEVICE_NAME}", f"saw: {names}")
            print("\n        The glove is off, out of range, or advertising a "
                  "different name.\n        The app filters on this exact name.\n")
            raise SystemExit(1)
        address = match.address
        record(PASS, f"advertising as {DEVICE_NAME}", address)

    async with BleakClient(address, timeout=20.0) as client:
        record(PASS, "connected", address)

        services = {s.uuid.lower() for s in client.services}
        if SERVICE_UUID in services:
            record(PASS, "exposes the SafeHer service", SERVICE_UUID)
        else:
            record(FAIL, "exposes the SafeHer service",
                   f"not found among {len(services)} services")
            raise SystemExit(1)

        characteristics = {
            c.uuid.lower() for s in client.services for c in s.characteristics
        }
        if CLASSIFICATION_UUID in characteristics:
            record(PASS, "classification characteristic", CLASSIFICATION_UUID)
        else:
            record(FAIL, "classification characteristic", "missing — no alarm is possible")
            raise SystemExit(1)

        has_telemetry = TELEMETRY_UUID in characteristics
        record(PASS if has_telemetry else WARN, "telemetry characteristic",
               TELEMETRY_UUID if has_telemetry else
               "absent — older firmware; the app tolerates this")

        classifications: list[tuple[float, str, float]] = []
        telemetry: list[str] = []
        malformed = 0

        def on_classification(_, data: bytearray) -> None:
            nonlocal malformed
            raw = data.decode("utf-8", "replace").strip()
            parts = raw.split(",")
            if len(parts) < 2:
                malformed += 1
                print(f"        malformed: {raw!r}")
                return
            try:
                confidence = float(parts[1])
            except ValueError:
                malformed += 1
                print(f"        malformed confidence: {raw!r}")
                return
            label = parts[0].strip().upper()
            classifications.append((asyncio.get_event_loop().time(), label, confidence))
            flag = "  <-- would count toward an alarm" if (
                label == "FALL" and confidence >= THRESHOLD) else ""
            print(f"        {label:<9} {confidence:.2f}{flag}")

        def on_telemetry(_, data: bytearray) -> None:
            telemetry.append(data.decode("utf-8", "replace").strip())

        await client.start_notify(CLASSIFICATION_UUID, on_classification)
        if has_telemetry:
            await client.start_notify(TELEMETRY_UUID, on_telemetry)

        print(f"\n  listening {args.seconds:.0f}s — wear the glove, move normally,")
        print("  then act out a fall near the end\n")
        await asyncio.sleep(args.seconds)

        await client.stop_notify(CLASSIFICATION_UUID)
        if has_telemetry:
            await client.stop_notify(TELEMETRY_UUID)

    print()
    if not classifications:
        record(FAIL, "notifies classifications",
               "none received — the model is not running or not notifying")
        raise SystemExit(1)

    rate = len(classifications) / args.seconds
    record(PASS, "notifies classifications",
           f"{len(classifications)} in {args.seconds:.0f}s ({rate:.1f}/s, expect ~2)")

    if malformed:
        record(FAIL, "payload format", f"{malformed} malformed — expected '<LABEL>,<confidence>'")
    else:
        record(PASS, "payload format", "every notification parsed")

    labels = Counter(label for _, label, _ in classifications)
    unknown = set(labels) - KNOWN_LABELS
    if unknown:
        record(WARN, "labels are known classes",
               f"unrecognised: {sorted(unknown)} — the app shows these as unknown")
    else:
        record(PASS, "labels are known classes", dict(labels))

    out_of_range = [c for _, _, c in classifications if not 0.0 <= c <= 1.0]
    if out_of_range:
        record(FAIL, "confidence within 0..1", f"saw {out_of_range[:3]}")
    else:
        record(PASS, "confidence within 0..1")

    if telemetry:
        sample = telemetry[-1]
        fields = sample.split(",")
        record(PASS, "telemetry notifies", f"{len(telemetry)} readings, last {sample!r}")
        # Zero is not absence on this wire. The app reads 0 bpm as "no sensor",
        # so sending it fabricates a reading it then has to discard.
        if len(fields) >= 3 and fields[2].strip() in {"0", "0.0", "0.00"}:
            record(WARN, "telemetry omits unmeasured fields",
                   "sending 0 for heart rate — send only the measured fields")
        else:
            record(PASS, "telemetry omits unmeasured fields", f"{len(fields)} fields")

    # Replay the app's own rule over what was just received.
    falls = [(t, c) for t, label, c in classifications
             if label == "FALL" and c >= THRESHOLD]
    would_fire = any(
        sum(1 for t2, _ in falls if 0 <= t2 - t1 <= WINDOW_SECONDS) >= REQUIRED_HITS
        for t1, _ in falls
    )
    print()
    if would_fire:
        record(PASS, "the app's alarm rule would fire",
               f"{REQUIRED_HITS} FALL >= {THRESHOLD} within {WINDOW_SECONDS:.0f}s")
    elif falls:
        record(WARN, "the app's alarm rule would fire",
               f"only {len(falls)} qualifying FALL — not enough within the window")
    else:
        record(WARN, "the app's alarm rule would fire",
               "no qualifying FALL seen — expected if you did not act one out")

    failures = sum(1 for status, _ in results if status == FAIL)
    warnings = sum(1 for status, _ in results if status == WARN)
    print("-" * 62)
    print(f"{len(results) - failures - warnings} passed, {warnings} warnings, "
          f"{failures} failures")
    if failures == 0:
        print("\nThe glove satisfies the contract. Pair it in the app:")
        print("  SafeHer > Devices > Pair Device\n")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    asyncio.run(main())
