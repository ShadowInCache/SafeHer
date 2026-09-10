"""Check a pair of SafeHer glasses against the contract, before the app is involved.

    python scripts/check_glasses.py
    python scripts/check_glasses.py --host 192.168.1.42 --seconds 15
    python scripts/check_glasses.py --detect        # also run the weapon model

## Why check the firmware separately from the app

If you pair first and nothing happens, the fault could be the firmware, the
network, mDNS, the app, or the model — and the app shows you one bit of
information: it did not work. This exercises the same contract the phone does
and says which part failed, in the order the phone would hit it.

Everything here is a real measurement of a real device. Nothing is simulated.

Requires: `pip install requests` (and `opencv-python onnxruntime` for --detect).
"""

from __future__ import annotations

import argparse
import io
import re
import socket
import sys
import time

DEFAULT_HOST = "safeher-glasses.local"
MAX_FRAME_BYTES = 2 * 1024 * 1024

PASS, FAIL, WARN = "PASS", "FAIL", "WARN"
results: list[tuple[str, str, str]] = []


def record(status: str, name: str, detail: str = "") -> None:
    results.append((status, name, detail))
    mark = {"PASS": "  ok  ", "FAIL": " FAIL ", "WARN": " warn "}[status]
    print(f"[{mark}] {name}" + (f" — {detail}" if detail else ""), flush=True)


def check_dns(host: str) -> str | None:
    """mDNS first, because release builds of the app cannot use a raw IP."""
    bare = host.split(":")[0]
    try:
        ip = socket.gethostbyname(bare)
    except OSError as error:
        record(FAIL, f"resolve {bare}", str(error))
        if bare.endswith(".local"):
            print("\n        mDNS is not resolving. Common causes: the router "
                  "filters multicast,\n        or 'client isolation' is on for "
                  "this network. The RELEASE Android build\n        cannot use "
                  "a raw IP — only safeher-glasses.local — so fix this before "
                  "pairing.\n")
        return None
    record(PASS, f"resolve {bare}", ip)
    return ip


def check_status(base: str) -> dict | None:
    import requests

    try:
        response = requests.get(f"{base}/status", timeout=5)
    except Exception as error:
        record(FAIL, "GET /status", str(error)[:90])
        return None

    if response.status_code != 200:
        record(FAIL, "GET /status", f"HTTP {response.status_code}")
        return None

    try:
        body = response.json()
    except Exception:
        record(FAIL, "GET /status", "not JSON")
        return None

    # The app refuses to pair without this exact field. Without it, pairing
    # would succeed against a router's admin page.
    if body.get("device") != "safeher-glasses":
        record(FAIL, "identifies as safeher-glasses",
               f"got device={body.get('device')!r} — the app will refuse this")
        return body

    record(PASS, "identifies as safeher-glasses",
           f"firmware {body.get('firmware', '?')}")

    if "battery" in body:
        battery = body["battery"]
        if battery == 0:
            record(WARN, "battery field",
                   "sending 0 — omit the field instead; the app reads 0 as 'no sensor'")
        else:
            record(PASS, "battery field", f"{battery}%")
    else:
        record(PASS, "battery field", "omitted (correct when no divider is fitted)")

    for stream in ("video", "audio"):
        if body.get(stream) is False:
            record(WARN, f"{stream} advertised", "firmware reports it is unavailable")
    return body


def check_stream(base: str, seconds: float) -> None:
    """Pull the MJPEG stream and verify every rule the phone's parser relies on."""
    import requests

    try:
        response = requests.get(f"{base}/stream", stream=True, timeout=10)
    except Exception as error:
        record(FAIL, "GET /stream", str(error)[:90])
        return

    content_type = response.headers.get("Content-Type", "")
    if "multipart/x-mixed-replace" not in content_type:
        record(FAIL, "stream content type", f"got {content_type!r}")
        return
    record(PASS, "stream content type", content_type)

    buffer = b""
    frames: list[bytes] = []
    missing_length = 0
    started = time.time()

    for chunk in response.iter_content(chunk_size=4096):
        buffer += chunk
        while True:
            end = buffer.find(b"\r\n\r\n")
            if end < 0:
                break
            headers = buffer[:end].decode("latin-1", "replace")
            match = re.search(r"(?i)content-length:\s*(\d+)", headers)
            if not match:
                missing_length += 1
                buffer = buffer[end + 4:]
                continue
            length = int(match.group(1))
            if len(buffer) < end + 4 + length:
                break
            frames.append(buffer[end + 4: end + 4 + length])
            buffer = buffer[end + 4 + length:]
        if time.time() - started > seconds:
            break
    response.close()

    elapsed = max(time.time() - started, 1e-6)

    if missing_length:
        record(FAIL, "Content-Length on every part",
               f"{missing_length} parts had none — the phone skips these")
    elif frames:
        record(PASS, "Content-Length on every part", f"{len(frames)} frames")

    if not frames:
        record(FAIL, "frames received", "none in the sample window")
        return

    fps = len(frames) / elapsed
    if fps >= 8:
        record(PASS, "frame rate", f"{fps:.1f} fps")
    else:
        record(WARN, "frame rate",
               f"{fps:.1f} fps — check PSRAM is enabled and WiFi is 2.4 GHz and close")

    # Every frame must be a whole JPEG: SOI at the front, EOI at the back.
    bad = sum(1 for f in frames if not (f[:2] == b"\xff\xd8" and f[-2:] == b"\xff\xd9"))
    if bad:
        record(FAIL, "frames are complete JPEGs", f"{bad} of {len(frames)} malformed")
    else:
        record(PASS, "frames are complete JPEGs", f"all {len(frames)}")

    sizes = [len(f) for f in frames]
    average = sum(sizes) / len(sizes)
    if max(sizes) > MAX_FRAME_BYTES:
        record(FAIL, "frame size under 2 MB",
               f"largest {max(sizes)/1e6:.2f} MB — the phone skips oversized parts")
    else:
        record(PASS, "frame size", f"avg {average/1000:.0f} kB, max {max(sizes)/1000:.0f} kB")

    try:
        from PIL import Image

        image = Image.open(io.BytesIO(frames[len(frames) // 2]))
        width, height = image.size
        if (width, height) == (640, 480):
            record(PASS, "resolution", "640x480 (VGA), as the model expects")
        else:
            record(WARN, "resolution", f"{width}x{height} — VGA is what the app assumes")
    except Exception:
        pass

    globals()["_frames"] = frames


def check_audio(base: str, seconds: float) -> None:
    import requests

    try:
        response = requests.get(f"{base}/audio", stream=True, timeout=10)
    except Exception as error:
        record(WARN, "GET /audio", f"{str(error)[:70]} (evidence only, not a threat signal)")
        return

    data = b""
    started = time.time()
    for chunk in response.iter_content(chunk_size=4096):
        data += chunk
        if time.time() - started > seconds:
            break
    response.close()

    if len(data) <= 44:
        record(WARN, "audio stream", "header only, no samples — check the mic ribbon")
        return

    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        record(WARN, "audio stream", "not a WAV header")
        return

    elapsed = max(time.time() - started, 1e-6)
    kbps = (len(data) - 44) / elapsed / 1000
    # 16 kHz, 16-bit mono is 32 kB/s.
    detail = f"{len(data)/1000:.0f} kB in {elapsed:.1f}s ({kbps:.0f} kB/s, expect ~32)"
    record(PASS if 20 <= kbps <= 45 else WARN, "audio stream", detail)


def check_detection() -> None:
    """Run the real weapon model over the frames just captured."""
    frames = globals().get("_frames")
    if not frames:
        record(WARN, "weapon model on live frames", "no frames captured")
        return

    sys.path.insert(0, ".")
    try:
        from fastapi_app.services import weapon_detector as detector
    except Exception as error:
        record(WARN, "weapon model on live frames", f"cannot import: {str(error)[:60]}")
        return

    if detector.weapon_status().value != "ready":
        record(WARN, "weapon model on live frames",
               f"model {detector.weapon_status().value} — pip install onnxruntime opencv-python-headless")
        return

    sampled = frames[:: max(1, len(frames) // 10)][:10]
    scored = 0
    best = (0.0, None)
    for frame in sampled:
        try:
            verdict = detector.analyse_frame(frame)
        except Exception:
            continue
        scored += 1
        if verdict.weapon_confidence > best[0]:
            best = (verdict.weapon_confidence, verdict.weapon_label)

    if not scored:
        record(FAIL, "weapon model on live frames", "no frame could be decoded")
        return

    record(PASS, "weapon model on live frames",
           f"scored {scored} frames; strongest {best[1] or 'nothing'} "
           f"at {best[0]:.2f}")
    print("\n        Hold a knife or a replica in view and re-run to see this rise.\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--seconds", type=float, default=8.0)
    parser.add_argument("--detect", action="store_true",
                        help="run the weapon model over the captured frames")
    args = parser.parse_args()

    print(f"\nChecking glasses at {args.host}\n" + "-" * 62)

    if check_dns(args.host) is None and args.host.endswith(".local"):
        print("\nStopping: the app's release build needs this name to resolve.")
        raise SystemExit(1)

    base = args.host if args.host.startswith("http") else f"http://{args.host}"
    if check_status(base) is None:
        print("\nStopping: /status must answer before anything else is worth testing.")
        raise SystemExit(1)

    check_stream(base, args.seconds)
    check_audio(base, min(args.seconds, 4.0))
    if args.detect:
        check_detection()

    failures = sum(1 for status, _, _ in results if status == FAIL)
    warnings = sum(1 for status, _, _ in results if status == WARN)
    print("-" * 62)
    print(f"{len(results) - failures - warnings} passed, {warnings} warnings, "
          f"{failures} failures")
    if failures == 0:
        print("\nThe glasses satisfy the contract. Pair them in the app:")
        print(f"  SafeHer > Devices > SafeHer Camera > {args.host}\n")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
