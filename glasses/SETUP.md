# SafeHer glasses — firmware setup

Board: **Seeed Studio XIAO ESP32-S3 Sense** (the *Sense* variant — the plain
XIAO ESP32-S3 has neither the camera connector nor the PDM microphone).

Sketch: [`SafeHer_Glasses_Stream/`](SafeHer_Glasses_Stream/)

## 1. Hardware

Clip the camera/microphone expansion board onto the XIAO and seat the ribbon
cable fully — a half-seated ribbon gives `camera init failed: 0x105`, which
reads like a software fault and is not one.

Use a **data** USB-C cable. Charge-only cables are the most common reason the
board never appears as a port.

## 2. Arduino IDE

**Board package.** File → Preferences → *Additional boards manager URLs*:

```
https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
```

Then Tools → Board → Boards Manager → install **esp32 by Espressif Systems**,
**version 3.0.0 or newer**. This matters: the sketch uses the ESP-IDF v5 I2S
API (`driver/i2s_pdm.h`), which does not exist in the 2.x package. On 2.x you
will get `fatal error: driver/i2s_pdm.h: No such file or directory`.

**Board:** Tools → Board → ESP32 Arduino → **XIAO_ESP32S3**

**Settings that are not optional:**

| Tools setting | Value | What breaks without it |
|---|---|---|
| **PSRAM** | **OPI PSRAM** | Camera falls back to one buffer and QVGA; the stream stutters and the app sees ~3 fps |
| **Partition Scheme** | **Huge APP (3MB)** | Sketch overflows flash and will not upload |
| **CPU Frequency** | 240 MHz | Frame rate drops |
| **USB CDC On Boot** | Enabled | No serial output, so no way to read the IP or diagnose anything |
| Flash Size | 8 MB | — |
| Upload Speed | 921600 | Slower is fine if uploads fail |

**One external library.** Sketch → Include Library → Manage Libraries →
install **WebSockets** by Markus Sattler. It serves the raw-PCM WebSocket on
port 81 that the standalone demo uses; the app itself does not need it, but the
sketch will not compile without it.

Everything else — `esp_camera`, `ESPmDNS`, `WiFi`, `driver/i2s_pdm.h` — ships
with the board package.

## 3. Credentials

```
cd glasses/firmware/SafeHer_Glasses_Stream
cp secrets.h.example secrets.h
```

Fill in `WIFI_SSID` and `WIFI_PASSWORD`. **`secrets.h` is gitignored — never
put credentials in the `.ino`.** The sketch this replaces had a Gmail app
password and an Arduino IoT device key committed to a public repository.

**2.4 GHz only.** The ESP32-S3 has no 5 GHz radio. If your router publishes one
SSID for both bands, the board may simply never associate; split the SSIDs or
use a 2.4 GHz guest network.

## 4. Flash

Open `SafeHer_Glasses_Stream.ino`, select the port, upload.

If the port does not appear, or the upload fails at "Connecting…": hold
**BOOT**, tap **RESET**, release **BOOT**, then upload. That is normal for this
board and not a fault.

## 5. Verify before touching the app

Open Serial Monitor at **115200**. A healthy boot prints:

```
SafeHer glasses starting
microphone: ready
connecting to WiFi....
mDNS: http://safeher-glasses.local/
video:  http://192.168.1.x/stream
audio:  http://192.168.1.x/audio
pair with: safeher-glasses.local
```

From a computer on the same WiFi:

| Check | Expect |
|---|---|
| `http://safeher-glasses.local/status` | `{"device":"safeher-glasses","firmware":"1.2.0","video":true,"audio":true}` |
| `http://safeher-glasses.local/stream` in a browser | Live video |
| `http://safeher-glasses.local/level` | `{"level_db":-42.3,"available":true}` — clap and watch it rise |
| `http://safeher-glasses.local/audio` | Downloads/plays a WAV stream |

**If `safeher-glasses.local` does not resolve but the raw IP works**, mDNS is
being blocked — some routers filter multicast, and "client isolation" or "AP
isolation" on a guest network blocks it outright. Worth fixing, because the
name is what the app is built around — but **the IP is a real fallback, in
release builds too** (see below).

**On a phone, that same symptom has a second cause.** Android's Wi-Fi chip
discards multicast not addressed to the phone unless the app holds a
`WifiManager.MulticastLock` — so the query goes out, the camera answers, and
the reply is dropped before the app sees it. The name fails while the raw IP
streams video perfectly. SafeHer takes that lock around every lookup
(`android/.../network/MulticastLockPlugin.kt`, with
`CHANGE_WIFI_MULTICAST_STATE` in the manifest), so a phone still failing by
name after a reinstall points at the router, not the app. A computer on the
same network is not a valid test of this: its OS resolves `.local` itself and
needs no such lock.

## 6. Pair with the app

SafeHer → **Devices** → **SafeHer Camera** → enter `safeher-glasses.local` →
**Connect**.

The app calls `/status` and refuses to save unless the reply identifies itself
as `safeher-glasses`, so a wrong address fails immediately rather than silently.

Weapon detection then runs while a **Safe Journey** is active. It does not run
outside one — the camera and microphone are the two most intrusive things the
app touches, and they stay tied to a boundary the user set herself.

## What the app reads

| Endpoint | Used today | Notes |
|---|---|---|
| `/stream` | **Yes** | Scored on the phone at ~5 fps. Video never leaves the phone; only a score is sent onward. |
| `/status` | **Yes** | Pairing and battery. |
| `/audio` | **Yes — evidence only** | Recorded during an emergency and uploaded with the incident. Not a threat signal. |
| `/level` | No | Served and working. |

**Why glasses audio is not the audio signal.** The phone's microphone is better
placed and its speech recogniser is already installed and better than anything
reachable over an I2S link. Android's `SpeechRecognizer` also cannot be fed a
remote stream, so glasses audio cannot simply be substituted — it would need
its own transcription path, which today means uploading it to the server.

**Evidence capture is now wired.** During an emergency the app pulls `/audio`
for up to two minutes and uploads it with the incident, alongside the phone's
own recording. It needs no microphone permission and contends with nothing,
because it is a network socket rather than the device microphone.

The remaining unbuilt use is a **loudness cue** from `/level` — a shout is loud
long before it is intelligible, and loudness survives wind and distance where a
transcript does not. It would be supporting context, never a fusion input.

## Tuning

Everything worth changing is a named constant at the top of the sketch.

| Constant | Default | Effect |
|---|---|---|
| `config.frame_size` | `FRAMESIZE_VGA` | The model input is 640×640. Larger is discarded at the resize. |
| `config.jpeg_quality` | `12` | Lower = better quality, bigger frames. Above ~18 the detector starts losing thin objects like knife blades. |
| `AUDIO_SAMPLE_RATE` | `16000` | Every speech model here expects 16 kHz. Raising it costs bandwidth and buys nothing. |
| `s->set_vflip` | `1` | Set to `0` if your camera is mounted the other way up. |

## Troubleshooting

| Symptom | Cause |
|---|---|
| `camera init failed: 0x105` | Ribbon cable not fully seated, or the plain XIAO ESP32-S3 rather than the Sense |
| `WARNING: no PSRAM` | Tools → PSRAM is not set to OPI PSRAM |
| `driver/i2s_pdm.h: No such file` | esp32 board package is 2.x; upgrade to 3.x |
| Sketch too big | Partition Scheme is not Huge APP |
| Stream stutters, ~3 fps | PSRAM off, or 5 GHz/weak WiFi, or `WiFi.setSleep` re-enabled |
| App says "not a SafeHer camera" | Something else answered on that address — check the IP |
| Works in debug, fails in release | **Not** the raw IP — Dart's HTTP stack never consults Android's cleartext policy, so an IP pairs in release too (verified 2026-09-16 on a signed release APK). Look at signing, permissions, or R8 instead |
| `microphone: UNAVAILABLE` | Expansion board not attached. Video and weapon detection still work; only the second evidence recording is lost |

## The contract

`docs/GLASSES_STREAM_PROTOCOL.md` is the authority on what the app expects.
Three things there are load-bearing and easy to break:

1. **`Content-Length` on every MJPEG part** — the phone's parser needs it.
2. **mDNS `safeher-glasses`** — so pairing never requires reading an IP off a
   serial monitor, and survives the camera getting a new lease.
3. **Omit battery rather than sending `0`** — the app treats zero as absent, so
   a fabricated zero and a flat battery must not look alike.
