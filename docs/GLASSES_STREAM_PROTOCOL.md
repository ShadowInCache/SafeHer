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

| Setting | Value | Why |
|---|---|---|
| `frame_size` | `FRAMESIZE_VGA` (640×480) | The model's input is 640×640; sending more resolution costs WiFi bandwidth and is thrown away on resize |
| `jpeg_quality` | ~12 | Lower numbers are higher quality on this driver. Around 12 keeps frames near 30–60 kB |
| `fb_count` | 2 | Requires PSRAM. One buffer stalls the capture loop while the previous frame is still being sent |
| `pixel_format` | `PIXFORMAT_JPEG` | The app expects JPEG bytes; anything else means decoding on the phone for no gain |

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
{ "device": "safeher-glasses", "firmware": "1.1.0",
  "video": true, "audio": true, "battery": 87 }
```

`video` and `audio` report which streams actually came up. `audio: false` is an
ordinary outcome — the expansion board may be absent, and the app does not use
glasses audio regardless.

`battery` is a percentage, or omitted if unknown. **Omit it rather than sending
`0`** — the app treats an implausible zero as absent, the same way it does for
the glove's heart rate, because "no reading" and "flat battery" must not look
alike.

## The change needed to the current firmware

`hardware/smart_glasses/Working_XIAO_ESP32_noise2/` currently does this after
cloud setup:

```c
WiFi.disconnect(true);
WiFi.mode(WIFI_OFF);
```

It then emails stills over SMTP. For streaming, **WiFi has to stay up** and an
HTTP server has to serve `/stream`. Email can stay or go; it is independent of
this interface.

## mDNS name — required for release builds

The firmware must advertise itself as **`safeher-glasses.local`**:

```c
MDNS.begin("safeher-glasses");
MDNS.addService("http", "tcp", 80);
```

This is not a convenience. Release builds of the Android app block cleartext
HTTP entirely — `network_security_config.xml` sets
`cleartextTrafficPermitted="false"` so that an attacker on the same cafe wifi
cannot strip TLS from traffic carrying a woman's location and evidence.

One exception is carved out, for exactly this hostname. Android's config cannot
express an IP range, so permitting "the local network" would mean permitting
cleartext to anything at all, which is the blanket setting that was removed in
the first place. **A raw IP address will therefore work in debug builds and
fail in release ones.** Serve the mDNS name.

TLS on the glasses is not the alternative. An ESP32-S3 cannot terminate it at
15 fps, and no certificate authority issues for a device on someone's home wifi.
What crosses this link is video that never leaves the phone afterwards — it is
scored on the device and only a number is sent onward.

## Pairing

The app stores one address in preferences (`glassesHost`), as `host` or
`host:port`, and builds `http://<host>/stream` from it. For release builds that
value must be `safeher-glasses.local`.

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

The firmware also serves `GET /audio` (16 kHz mono WAV, streaming PCM) and
`GET /level` (a single RMS figure in dBFS). **Neither is read by the app
today**, and `/status` advertises `"audio": true|false` so a future client can
tell whether the microphone came up.

`/audio` **is** now consumed, for one purpose: evidence. During an emergency the
app records it alongside the phone's own microphone, capped at two minutes or
4 MB, and uploads it as a second `audio/wav` file on the incident. A microphone
on the wearer's head is better placed than one in a bag, and because this is a
network socket rather than the device microphone, it contends with nothing —
the phone recording and threat listening both continue.

It is still **not** a threat signal and feeds nothing into the fusion. `/level`
remains unconsumed.

## Not part of this contract

The glasses' microphone is **not** used for the audio threat signal. That runs
on the phone's own microphone through the platform speech recogniser, which is
better placed, better than anything achievable over an I2S link, and already
installed. Android's `SpeechRecognizer` also cannot be fed a remote stream, so
glasses audio could not simply be substituted for it — it would need its own
transcription path. See `mobile/assets/models/README.md`.
