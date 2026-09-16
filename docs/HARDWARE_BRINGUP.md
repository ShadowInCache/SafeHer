# Hardware bring-up

The first time a real glove or real glasses meet the app. Everything up to now
has been tested against fakes — a synthetic MJPEG stream, a fake BLE service —
so this is the day the assumptions get checked.

**Work outward.** Firmware alone, then the contract, then the app, then the
whole path. Skipping to "pair it and see" gives you one bit of information when
something fails, and there are five places it could have failed.

Budget about **90 minutes** for both devices if nothing is wrong, and expect
something to be wrong.

---

## Before you start

```bash
pip install requests pillow bleak
```

Both devices and the laptop on the **same 2.4 GHz WiFi**. The ESP32-S3 has no
5 GHz radio, and if your router publishes one SSID for both bands the board may
simply never associate.

---

## Stage 1 — Glasses, firmware only

Flash `glasses/firmware/SafeHer_Glasses_Stream/` following
[`glasses/SETUP.md`](../glasses/SETUP.md). The board settings there are not
optional; three of them fail in ways that read as software faults.

Serial Monitor at 115200. A healthy boot says:

```
microphone: ready
mDNS: http://safeher-glasses.local/
video:  http://192.168.1.x/stream
```

Then, from the laptop:

```bash
python scripts/check_glasses.py
```

This exercises the same contract the phone does, in the same order, and names
the step that failed. It checks mDNS resolution, that `/status` identifies
itself as `safeher-glasses`, that **every** MJPEG part carries a
`Content-Length`, the frame rate, that each frame is a complete JPEG, the
resolution, and the audio stream's data rate.

| It says | Do this |
|---|---|
| `FAIL resolve safeher-glasses.local` | mDNS is blocked — router multicast filtering or AP/client isolation. Pass `--host <ip>` to keep going; the app pairs by IP too, release builds included |

This script runs on a laptop, whose OS resolves `.local` itself. **The phone is
a different test**, and it can fail for two independent reasons:

1. **Receiving.** Android's Wi-Fi chip discards multicast replies unless the app
   holds a `WifiManager.MulticastLock`. SafeHer takes one around every lookup
   (`MulticastLockPlugin.kt`).
2. **Sending.** With mobile data and WiFi up at once, the query to `224.0.0.251`
   leaves over whichever network Android has made the *default* — usually
   cellular when the WiFi has no internet — and never reaches the LAN. Unicast
   to the camera still works, because RFC1918 addresses route over WiFi.

So a phone that pairs by IP but not by name has one of those two, not a broken
camera. Turning mobile data off is the quickest way to tell them apart:
if the name then resolves, it was the second.
| `FAIL identifies as safeher-glasses` | Something else answered on that address. The app will refuse it too |
| `FAIL Content-Length on every part` | The phone's parser cannot find frame boundaries — firmware bug, see the protocol doc |
| `warn frame rate 3 fps` | PSRAM is off in Tools, or WiFi is weak/5 GHz |
| `warn audio stream: header only` | Mic ribbon not seated. Video still works; only the second evidence recording is lost |

When it passes, run it again with the model in the loop:

```bash
python scripts/check_glasses.py --detect
```

That scores ten real frames with the real weapon model. **Hold a knife or a
replica in view and re-run** — the strongest detection should rise well above
its 0.35 reporting floor. If it does, the entire vision path is proven before
the phone has been touched.

---

## Stage 2 — Glove, firmware only

Flash **`glove/firmware/SafeHer_Glove_V5_OnDevice/`** — the only sketch carrying
the current 5-class model. Check `DATA_COLLECTION_MODE` is **`0`** first: at `1`
(used when recording training data) BLE is never started and the glove is
invisible to the app and to this script. The Serial Monitor tells you which you
have within a second: raw CSV at 100 Hz means mode `1`.

Then close the SafeHer app — a BLE peripheral holds one connection, and if the
phone has it this script cannot see the glove.

```bash
python scripts/check_glove.py --seconds 60
```

Wear it, move normally for most of the window, then act out a fall near the end.

It verifies the advertised name, the service and characteristic UUIDs, the
`<LABEL>,<confidence>` payload format, that labels are among the five known
classes (`NORMAL`, `SUDDEN_MOVEMENT`, `SHAKING`, `TWISTING`, `FALL`), and that
confidence stays in range. It also recognises the two ways a board can be
running the wrong sketch: the `CLASS=…,CONFIDENCE=…` payload of
`SafeHer_Glove_Final`, and the retired `PUSH`/`PULL`/`JERK` labels. It prints every classification as
it arrives, so you can see what the glove thinks you are doing.

Then it **replays the app's own alarm rule** — two `FALL` at or above 0.75
within five seconds — over what it just received, and tells you whether the app
would have fired.

| It says | Meaning |
|---|---|
| `FAIL advertising as SafeHer-Glove` | `DATA_COLLECTION_MODE 1`, off, out of range, the phone still holds the connection, or a different name |
| `warn payload format 'CLASS=..'` | `SafeHer_Glove_Final` is flashed — the app reads it, but it carries the retired model |
| `warn model version` | The retired 7-class model is flashed |
| `FAIL exposes the SafeHer service` | Wrong service UUID — firmware and `glove_protocol.dart` disagree |
| `FAIL notifies classifications` | Connected, but the model is not running or not notifying |
| `warn telemetry omits unmeasured fields` | Sending `0` for heart rate. Zero is not absence on this wire |
| `warn the app's alarm rule would fire` | Expected if you did not act out a fall. Concerning if you did |

**Watch for false positives too.** Set the glove down firmly, drop a bag,
open a jar. Any `FALL` above 0.75 during ordinary movement is a real finding —
`normal_020` in the training set does exactly this at 0.987 confidence, and no
threshold fixes a misread that confident. It needs more data of that kind.

---

## Stage 3 — Pair with the app

Only once both scripts pass.

**Glasses** — SafeHer → Devices → **SafeHer Camera** → `safeher-glasses.local`
→ Connect. The app calls `/status` and refuses to save unless the device
identifies itself, so a wrong address fails immediately rather than silently.

**Glove** — SafeHer → Devices → **Pair Device**.

The Devices screen should now show the camera as set up and the glove as
connected.

---

## Stage 4 — End to end

Start a **Safe Journey**. Detection runs only during one — the camera and
microphone stay tied to a boundary the user sets herself.

Then check each signal reaches the fusion, one at a time:

| Signal | How to trigger it | What should happen |
|---|---|---|
| **Weapon** | Hold a knife or replica in the glasses' view for ~5 seconds | Score rises over a 15-frame window, then decays when removed |
| **Audio** | Say a held-out distress phrase clearly | Score rises for that utterance |
| **Glove** | Act out a fall | Countdown opens — the direct BLE path, no server involved |

Watch the backend log for `POST /alerts/analyze` arriving about once a second
while armed.

**Then the whole thing.** Trigger two signals together and let the countdown
run to dispatch. Confirm: contacts notified, GPS attached, audio evidence
uploaded, and — if the glasses are paired — a **second** audio file from the
glasses on the same incident.

Confirm **exactly one** alert. Two would mean the 60-second dedup window is not
holding.

---

## What to write down

Whatever happens, record it — this is the first real-world data the project has.

- Frame rate and average frame size actually achieved
- Whether the weapon model fired on a real knife, and at what confidence
- Any false `FALL` during ordinary movement, and what you were doing
- Battery life under continuous streaming — **currently uncharacterised**, and
  the only way to find out is to run it flat
- Whether mDNS worked on your network without intervention

---

## Two things that will not work, by design

**Web has no on-device weapon detection.** `ultralytics_yolo` is Android-only;
on web the app uploads a frame every two seconds to the server instead. That is
a weaker guarantee and the app publishes which one is running.

**The glasses' microphone is not the audio threat signal.** It is recorded as
evidence during an emergency. The threat signal comes from the *phone's*
microphone, because Android's speech recogniser cannot be fed a remote stream.
