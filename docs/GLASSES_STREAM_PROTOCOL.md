# Glasses video stream — the contract between firmware and app

The SafeHer glasses are a **XIAO ESP32-S3 Sense**: OV camera, PDM microphone on
I2S, PSRAM. The app treats them as one thing only — a source of JPEG frames over
the local network. This document is the whole interface. If the firmware
satisfies it, weapon detection works; nothing else about the firmware is the
app's business.

## What the app does with the frames

Frames are pulled over WiFi to the phone and scored there by YOLOv8n
(`weapon_yolov8n_fp16.tflite`, mAP@0.5 0.906). **Video never leaves the phone.**
Only the resulting number is sent to the server, alongside the glove and audio
signals, for `threat_fusion` to weigh.

Inference does not run on the glasses and cannot. YOLOv8n needs roughly two
orders of magnitude more compute and memory than an ESP32-S3 has —
`WEAPON_INFERENCE_PLACEMENT.md` has the arithmetic. The glasses' job is to see
and to send.

## Required endpoint

```
GET /stream
```

Response headers:

```
HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace; boundary=frame
```

Then, repeating without end:

```
--frame\r\n
Content-Type: image/jpeg\r\n
Content-Length: <exact byte length of the JPEG>\r\n
\r\n
<JPEG bytes>\r\n
```

**`Content-Length` is required on every part.** The parser
(`mobile/lib/features/devices/data/mjpeg_client.dart`) uses it to know where a
frame ends. A part without one is skipped, and a part whose length exceeds 2 MB
is treated as a desynchronised stream and skipped too — an unbounded read on a
corrupt length never recovers, and would eventually take the phone's memory with
it.

This is the stock `esp32-camera` `CameraWebServer` shape. It does not need to be
written from scratch.

### Settings that match what the app expects

These are the values the **shipped firmware actually uses**, which are not the
values this table gave until 2026-09-28. It specified VGA at quality 12 with two
buffers; the sketch has been QVGA at quality 20 with one buffer, and a comment in
it records why. The table was describing an intention, not the build.

| Setting | Value in firmware | Why |
|---|---|---|
| `frame_size` | `FRAMESIZE_QVGA` (320×240) | Chosen for stream stability: at VGA the stream stuttered. **The cost is unmeasured** — the model's input is 640×640, so these frames are upscaled, and upscaling is precisely what loses a thin blade |
| `jpeg_quality` | 20 | Lower numbers are higher quality on this driver. 20 is **above the ~18 where the detector begins losing thin objects**, and was chosen for stability rather than accuracy |
| `fb_count` | 1 | Two requires PSRAM and avoids stalling the capture loop while the previous frame is still going out. One was chosen alongside QVGA |
| `pixel_format` | `PIXFORMAT_JPEG` | The app expects JPEG bytes; anything else means decoding on the phone for no gain |

### What the combination costs — measured 2026-10-03

It used to say here that nothing had measured this. It has now been measured, on
**250 held-out weapon images** from the same merged test set the model was
validated against, scored through the real detector at the app's own operating
threshold (`WeaponScorer.confidenceFloor = 0.55`):

| Condition | Detected | Mean confidence |
|---|---|---|
| Native resolution (baseline) | **91.2%** | 0.780 |
| QVGA only, near-lossless | 89.2% | 0.755 |
| Full resolution, heavy compression | 90.4% | 0.776 |
| **QVGA + compression** | **80.8% – 88.4%** | 0.696 – 0.747 |

**Neither setting is the problem on its own, and together they are.** Dropping to
QVGA costs 2.0 points. Compressing hard at full resolution costs 0.8. If the
effects were additive the pair would cost under 3 — the measured cost reaches
**10.4**, roughly four times that.

The reason is the interaction, not either setting. At 320×240 a knife blade is a
few pixels wide; JPEG then quantises away precisely the high-frequency detail
that remains. At full resolution the blade spans enough pixels to survive the
same quantisation.

**Where the firmware sits.** esp32-camera's `jpeg_quality` is 0–63 with *lower*
meaning better, so its 20 is not libjpeg's 20. It lands around the
`qvga_q70`–`qvga_q85` band above: a **2.8–5.6 point** loss per frame. The scorer
then votes over 15 frames, which absorbs most of a few points of per-frame
recall — so the shipped settings are defensible, which is the opposite of what
this section previously implied.

**The cheap improvement is quality, not resolution.** Raising resolution is what
destabilised the stream. Compression at full resolution cost almost nothing, and
QVGA is where it compounds — so lowering the `jpeg_quality` *number* (better
quality, larger frames) buys back 2–3 points without touching frame size.

Two caveats. This used the server's **ONNX** export; the phone runs the
**TFLite fp16** build, same lineage but differently quantised. And it measures
single-frame recall on dataset images, not a real knife in a real room.

**Target 10–15 fps.** The app tolerates less. It deliberately runs inference at
about 5 fps regardless of how fast frames arrive, because the scorer votes over
a window spread across seconds — what it needs is coverage over time, not every
frame — and continuous inference at 15 fps would heat the phone for no
detection benefit.

## Also required

```
GET /status
```

Returning JSON, used for pairing and for showing battery in the app:

```json
{ "device": "safeher-glasses", "firmware": "1.2.0",
  "video": true, "audio": true, "battery": 87 }
```

The shipped firmware reports `1.2.0` and omits `battery`, because no divider is
fitted. Omission is the contract, not an oversight — see below.

`video` and `audio` report which streams actually came up. `audio: false` is an
ordinary outcome — the expansion board may be absent, and the app does not use
glasses audio regardless.

`battery` is a percentage, or omitted if unknown. **Omit it rather than sending
`0`** — the app treats an implausible zero as absent, the same way it does for
the glove's heart rate, because "no reading" and "flat battery" must not look
alike.

## Historical note — the sketch this replaced

`glasses/firmware/legacy_noise_alarm/` did this after cloud setup:

```c
WiFi.disconnect(true);
WiFi.mode(WIFI_OFF);
```

and then emailed stills over SMTP. With WiFi off there is no stream at all, so
it could not be extended into this contract. **That work is done**:
`SafeHer_Glasses_Stream` keeps WiFi up and serves the endpoints above. This
section is kept only so the change is traceable — it is no longer a task.

The legacy sketch also has a Gmail app password and an Arduino IoT device key
written into its source, and it is still tracked in this repository. Treat both
as compromised.

## mDNS name — how the app is meant to find the glasses

The firmware must advertise itself as **`safeher-glasses.local`**:

```c
MDNS.begin("safeher-glasses");
MDNS.addService("http", "tcp", 80);
```

`network_security_config.xml` sets `cleartextTrafficPermitted="false"` with one
exception carved out for exactly this hostname, so that an attacker on the same
cafe wifi cannot strip TLS from traffic carrying a woman's location and
evidence. Android's config cannot express an IP range, so permitting "the local
network" would mean permitting cleartext to anything at all, which is the
blanket setting that was removed in the first place.

**That policy does not reach this traffic.** It governs Android's Java/Kotlin
HTTP stacks; Dart's `HttpClient` is native and never consults it, so a raw IP
pairs in a release build too — verified 2026-09-16 on a signed release APK that
paired with `10.66.78.183`. This document previously claimed the opposite.

Serve the mDNS name anyway: it survives a new DHCP lease, and it means nobody
has to read an address off a serial monitor to pair. The IP is the fallback for
when multicast is blocked, not a debug-only trick.

TLS on the glasses is not the alternative. An ESP32-S3 cannot terminate it at
15 fps, and no certificate authority issues for a device on someone's home wifi.
What crosses this link is video that never leaves the phone afterwards — it is
scored on the device and only a number is sent onward.

## Pairing

The app stores one address in preferences (`glassesHost`), as `host` or
`host:port`, and builds `http://<host>/stream` from it. Either
`safeher-glasses.local` or a raw IP works, in debug and release alike.

**There is no default and no guess.** With no address stored, the app reports
the weapon signal as *absent* rather than as zero. That distinction is
load-bearing: absent means "nothing looked", zero means "something looked and
saw calm", and a default like `192.168.4.1` would let the app claim to be
watching whatever happened to answer on that address.

Both approaches work for the network itself:

- **Glasses as access point.** Simple, no router needed; the phone loses its
  normal internet connection while attached, which matters because the fused
  score is computed server-side.
- **Both on the same WiFi.** Preferred. Keeps the phone's data connection, so
  scores keep reaching the server.

## What the app does when the stream dies

It reconnects with exponential backoff from 2 s to 30 s, and reports
`GlassesStreamStatus.disconnected` while it is down. The detection window is
**cleared** on disconnect: a knife seen once before a dropout and once a minute
after is two glimpses, not persistence, and letting them vote together would
invent evidence nobody observed.

A dead stream reads as "not watching". It must never read as "watching and
seeing nothing" — those are opposite claims, and the second one tells a woman
she is covered when she is not.

## Audio endpoints

The firmware serves two, and `/status` advertises `"audio": true|false` so a
client can tell whether the microphone came up at all.

### `GET /audio`

16 kHz mono WAV, streaming PCM, declared length `0xFFFFFFFF` because a live
microphone has no length in advance — readers take bytes until the connection
closes.

**Consumed, for one purpose: evidence.** During an emergency the app records it
alongside the phone's own microphone, capped at two minutes or 4 MB, and uploads
it as a second `audio/wav` file on the incident. A microphone on the wearer's
head is better placed than one in a bag, and because this is a network socket
rather than the device microphone it contends with nothing — the phone recording
and threat listening both continue.

It is **not** a threat signal and feeds nothing into the fusion.

### `GET /level`

```json
{ "level_dbfs": -42.30, "peak_dbfs": -31.00, "available": true }
```

RMS of the current buffer in dBFS, plus a peak that decays to the noise floor
over roughly two seconds so a shout survives until the next poll. Measured on
the DC-removed sample **before** the firmware's 12× voice gain: taken after it,
the figure would describe the amplifier rather than the room and would sit
pinned near full scale through any ordinary conversation.

`{"available": false}` — with no level fields at all — until a microphone read
has actually succeeded. A client must read that as *unknown*, never as quiet: an
unseated ribbon cable reporting a convincing −120 dB would look exactly like a
calm room.

It costs a few dozen bytes per request, against roughly 32 kB/s for `/audio`,
which makes it the only part of the microphone affordable to consult
continuously. **Nothing on the phone polls it yet.**

## Not part of this contract

The glasses' microphone is **not** used for the audio threat signal. That runs
on the phone's own microphone through the platform speech recogniser, which is
better placed, better than anything achievable over an I2S link, and already
installed. Android's `SpeechRecognizer` also cannot be fed a remote stream, so
glasses audio could not simply be substituted for it — it would need its own
transcription path. See `mobile/assets/models/README.md`.
