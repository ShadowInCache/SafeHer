# SafeHer Smart Glasses

A XIAO ESP32-S3 Sense that streams **video and audio to the phone over WiFi**.
It runs no model. The phone does the seeing.

That division is deliberate and not negotiable: YOLOv8n needs roughly two
orders of magnitude more compute and memory than this part has, and the
arithmetic is written out in `docs/WEAPON_INFERENCE_PLACEMENT.md`. The glasses
capture and transmit; the phone scores and decides. Video never leaves the
phone — only a number does.

Contrast with the glove, which is the opposite arrangement: the glove runs its
own model on the ESP32 and reports a *conclusion* over BLE. The glasses report
*raw frames* over WiFi. Each sensor's model lives wherever it fits.

```text
hardware/smart_glasses/
├── SafeHer_Glasses_Stream/          ← the one the app uses
│   ├── SafeHer_Glasses_Stream.ino   Camera, mic, HTTP server, mDNS
│   └── secrets.h.example            Copy to secrets.h (gitignored)
├── SETUP.md                         Board settings, flashing, verification
├── smart_glasses.ino                Legacy. Does not compile — see below
└── Working_XIAO_ESP32_noise2/       Legacy. Noise alarm, superseded
```

Full flashing instructions, board settings and troubleshooting are in
[SETUP.md](SETUP.md). This file is the *contract* — what it serves and why.

---

## How it works

| | |
|---|---|
| **Board** | Seeed XIAO ESP32-S3 **Sense** — the plain S3 has no camera or mic |
| **Camera** | OV series, JPEG straight from the sensor |
| **Video** | 640×480 (VGA), quality 12, 2 frame buffers in PSRAM, 10–15 fps |
| **Microphone** | PDM over I²S, pins 42 (clock) and 41 (data) |
| **Audio** | 16 kHz, 16-bit, mono |
| **Link** | WiFi 2.4 GHz only — the S3 has no 5 GHz radio |
| **Discovery** | mDNS, `safeher-glasses.local` |

### Endpoints

| Route | Serves | Consumed by the app |
|---|---|---|
| `GET /stream` | MJPEG, `multipart/x-mixed-replace` | **Yes** — weapon detection |
| `GET /status` | JSON identity, firmware, battery | **Yes** — pairing |
| `GET /audio` | Streaming WAV, 16 kHz mono | **Yes** — evidence only |
| `GET /level` | JSON loudness in dBFS | No — see *Not built* below |

---

## Three things that are wire contract, not preference

**1. `Content-Length` on every MJPEG part.** The phone's parser uses it to find
where a frame ends. A part without one is skipped; a part claiming more than
2 MB is treated as a desynchronised stream and skipped too, because an
unbounded read on a corrupt length never recovers and would eventually take the
phone's memory with it.

**2. The mDNS name `safeher-glasses`.** Release builds of the Android app deny
cleartext HTTP everywhere except that one hostname — the exception exists so an
attacker on the same café WiFi cannot strip TLS from traffic carrying a woman's
location and her evidence. **A raw IP address works in a debug build and fails
in a release build.** This is the single most common way the glasses appear to
work in development and are unreachable in production.

**3. Omit `battery` rather than sending `0`.** The app treats an implausible
zero as *absent*, exactly as it does for the glove's heart rate. "No reading"
and "flat battery" must not look alike, and a fabricated zero makes them
identical.

The pairing check is worth knowing about too: the app refuses to save an
address unless `/status` answers with `"device":"safeher-glasses"`. Without
that, pairing would succeed against a router's admin page and the app would
claim a camera it does not have.

---

## What the app does with each stream

**Video** feeds weapon detection. Frames are parsed on the phone, and YOLOv8n
runs at about **5 fps** — deliberately throttled below the frame rate, because
the scorer votes over a 15-frame window spread across seconds. What it needs is
coverage over time, not every frame, and inferring at 15 fps would heat the
phone for no detection benefit. Frames arriving while inference is still
running are dropped rather than queued: on a safety signal, a queue is a
machine for reporting the past.

Detection runs **only while a Safe Journey is active**. The camera is the most
intrusive thing the app touches, and it stays tied to a boundary the user sets
herself.

**Audio** is recorded as evidence during an emergency, capped at two minutes or
4 MB, and uploaded with the incident alongside the phone's own recording. The
argument is position: the phone is in a bag or a hand that has been knocked
away; the glasses are on her head. It is also the only capture path that does
not compete for the phone's microphone, because it is a network socket rather
than the device.

**Audio is not a threat signal.** The audio score comes from the *phone's*
microphone through the platform speech recogniser, which is better placed,
already installed, and better than anything reachable over an I²S link. Android's
`SpeechRecognizer` also cannot be fed a remote stream, so glasses audio could
not simply be substituted for it — it would need its own transcription path.

---

## When the stream dies

The app reconnects with exponential backoff from 2 s to 30 s and reports the
link as disconnected while it is down. The detection window is **cleared** on
disconnect: a knife seen once before a dropout and once a minute after is two
glimpses, not persistence, and letting them vote together would invent evidence
nobody observed.

A dead stream reads as "not watching". It must never read as "watching and
seeing nothing" — those are opposite claims, and the second one tells a woman
she is covered when she is not.

---

## Two legacy sketches, kept for reference only

**`smart_glasses.ino`** — targets an **AI-Thinker ESP32-CAM**, not this board,
and streams base64 frames over MQTT to a server. It **does not compile**: it
includes `camera_pins.h` and `fb_gv.h`, neither of which exists in this
repository. Do not flash it and do not treat it as a starting point.

**`Working_XIAO_ESP32_noise2/`** — the sketch that actually ran on this board
before streaming existed. It detects loud noise, captures a still, and emails it
over SMTP via Arduino IoT Cloud. Two reasons it is superseded rather than
extended:

* it calls `WiFi.disconnect(true)` after setup so it can listen undisturbed,
  and with WiFi off there is no stream at all;
* **it has a Gmail app password and an Arduino IoT device key written into the
  source**, both pushed to a public repository. Treat those credentials as
  compromised regardless of whether they were ever used. The replacement keeps
  secrets in a gitignored `secrets.h`.

---

## Status

**Working and consumed:** video streaming, status/pairing, audio evidence
capture, mDNS discovery, WiFi auto-reconnect.

**Never verified on hardware.** No pair of glasses has been flashed with
`SafeHer_Glasses_Stream` and paired with the app. Everything on the app side is
tested against a synthetic MJPEG stream — including a parser test that cuts the
body at *every* byte offset — but the firmware itself has not run.

That is the honest gap, and it is the next thing to close. [SETUP.md](SETUP.md)
§5 is a verification sequence you can run from a browser before the app is
involved at all.

---

## Not built

**A loudness cue from `/level`.** A shout is loud long before it is
intelligible, and loudness survives wind, distance and a mouth turned away
where a transcript does not. It would be *supporting context* on an incident,
never a fusion input — the threat score has exactly three signals by design,
and adding a fourth is the change the architecture test exists to prevent.

**Battery reporting.** `batteryPercent()` returns −1 unless `BATTERY_ADC_PIN`
is defined, and no divider is fitted. Battery life, weight and continuous
operating time have not been characterised.
