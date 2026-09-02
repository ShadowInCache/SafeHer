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
| `FAIL resolve safeher-glasses.local` | mDNS is blocked — router multicast filtering or AP/client isolation. **Fix before pairing**: the release build cannot use a raw IP. To keep going meanwhile, pass `--host <ip>` |
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

```bash
python scripts/check_glove.py --seconds 60
```

Wear it, move normally for most of the window, then act out a fall near the end.

It verifies the advertised name, the service and characteristic UUIDs, the
`<LABEL>,<confidence>` payload format, that labels are among the seven known
classes, and that confidence stays in range. It prints every classification as
it arrives, so you can see what the glove thinks you are doing.

Then it **replays the app's own alarm rule** — two `FALL` at or above 0.75
within five seconds — over what it just received, and tells you whether the app
would have fired.

| It says | Meaning |
|---|---|
| `FAIL advertising as SafeHer-Glove` | Off, out of range, or a different name. The app filters on this exact string |
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
