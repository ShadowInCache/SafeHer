"""Cover, contents and sections 1-6."""

import os

from PIL import Image as PILImage
from reportlab.lib.units import mm
from reportlab.platypus import HRFlowable, Image, PageBreak, Paragraph, Spacer

from blocks import BULLETS, FIG, FLOW, H1, H2, H3, KV, NOTE, NUMBERED, P, SP, TBL
from style import ACCENT, INK, RULE, S

FIGDIR = "docs/assets/evaluation"


def cover():
    f = [Spacer(1, 22 * mm)]
    logo = "docs/assets/safeher-logo.png"
    if os.path.exists(logo):
        with PILImage.open(logo) as im:
            w, h = im.size
        scale = (22 * mm) / h
        img = Image(logo, width=w * scale, height=h * scale)
        img.hAlign = "LEFT"
        f.append(img)
        f.append(Spacer(1, 12 * mm))
    else:
        f.append(Spacer(1, 16 * mm))
    f.append(Paragraph("TECHNICAL PROJECT DESCRIPTION", S["coverlabel"]))
    f.append(Paragraph("SafeHer", S["title"]))
    f.append(Paragraph(
        "A multi-modal wearable threat-detection and emergency-dispatch "
        "system, with the evidence for every claim made about it.",
        S["subtitle"]))
    f.append(Spacer(1, 14 * mm))
    f.append(HRFlowable(width="38%", thickness=2, color=ACCENT, spaceAfter=14))
    f.append(KV([
        ("Document", "Project explanation accompanying the test and evaluation report"),
        ("Revision", "2026-11-04"),
        ("System version", "Mobile application 1.0.0 (build 5); backend FastAPI; "
                           "firmware ESP32-C3 glove and XIAO ESP32-S3 Sense glasses"),
        ("Repository", "ShadowInCache/SafeHer"),
        ("Author", "Akshay"),
    ], label_w=26))
    f.append(Spacer(1, 16 * mm))
    f.append(NOTE(
        "Reading this document",
        [
            "Sections 1 to 8 explain what the system is and how it works. "
            "Sections 9 to 12 give the measurements behind it, and section 14 "
            "states plainly what the system has <b>not</b> been shown to do.",
            "Every quantity in this document is traceable to a named script run "
            "against a named artifact over data the model in question never "
            "trained on. Where a figure is a calculation rather than an "
            "observation, it is labelled as one. Nothing here is an estimate "
            "presented as a measurement.",
        ]))
    return f


def contents():
    f = [Paragraph("Contents", S["h1"]),
         HRFlowable(width="100%", thickness=1.2, color=ACCENT,
                    spaceBefore=5, spaceAfter=14)]
    items = [
        ("1", "About this document", [
            "Evidence grading", "The standing rule"]),
        ("2", "The system in brief", [
            "The problem", "What the system does", "Component inventory"]),
        ("3", "Hardware", [
            "Smart Glove", "Smart Glasses", "Where each model runs, and why",
            "The phone"]),
        ("4", "Software architecture", [
            "The three tiers", "The phone as gateway", "Storage"]),
        ("5", "The detection subsystems", [
            "Motion", "Weapon", "Voice", "Facial expression"]),
        ("6", "Threat fusion", [
            "The weights", "Six mechanisms", "Absent is not zero",
            "A worked example"]),
        ("7", "The two alarm paths", []),
        ("8", "Evidence capture and chain of custody", []),
        ("9", "Measured results: weapon detection", []),
        ("10", "Measured results: voice distress", []),
        ("11", "Measured results: motion", []),
        ("12", "Conformance against the specification's own targets", []),
        ("13", "Hardware bring-up, 4 November 2026", []),
        ("14", "What this system has not been shown to do", []),
        ("15", "Reproducibility", []),
    ]
    for num, title, subs in items:
        f.append(Paragraph(f"{num}&#160;&#160;{title}", S["toc1"]))
        for s in subs:
            f.append(Paragraph(s, S["toc2"]))
    return f


def s1():
    f = H1("1", "About this document")
    f.append(P(
        "SafeHer is a wearable personal-safety system: two ESP32-class devices, "
        "a mobile application and a backend service, which together try to "
        "notice that a person is in danger and get help moving before she has "
        "to operate a phone. This document explains how the system is built "
        "and what it has been measured to do.", "lead"))
    f.append(P(
        "It accompanies the test and evaluation report already submitted. "
        "Where the two overlap, the evaluation report is the primary record: "
        "it carries the full per-class tables, confusion matrices and script "
        "provenance. This document is the explanation that makes those numbers "
        "legible — what the parts are, how a signal becomes an alarm, and "
        "which claims the evidence does and does not support."))

    f.append(H2("1.1&#160;&#160;Evidence grading"))
    f.append(P(
        "Mixing an observation with a calculation is the most common way a "
        "technical report overstates itself, so the underlying evaluation data "
        "grades every figure. The same grades are used here."))
    f.append(TBL(
        ["Grade", "What it means"],
        [
            ["Measured",
             "Real inference over real data with real ground-truth labels, "
             "reproducible from a named script."],
            ["Simulated",
             "Real inference, but over inputs synthesised to stand in for data "
             "that was not available — for example stills jittered into "
             "pseudo-video frames."],
            ["Derived",
             "Not an observed event. Computed by feeding measured values "
             "through the system's own formulas and constants."],
            ["Documented, not verified",
             "Copied from a training log or code comment and not re-measured. "
             "Must not be quoted as a tested figure."],
        ],
        widths=[22, 78]))
    f.append(SP(10))
    f.append(P(
        "Two consequences are worth stating. The 4.8 per cent solo auto-SOS "
        "exposure in section 11 is <i>derived</i>: no alert was dispatched to "
        "produce it. The facial-expression accuracy figures that appear in "
        "earlier project documentation are <i>documented, not verified</i>, "
        "which is one reason that model is barred from the threat decision "
        "altogether."))

    f.append(H2("1.2&#160;&#160;The standing rule"))
    f.append(NOTE(
        "The rule this project is built under",
        "Every claim must be supported by a measurement on data the model "
        "never trained on, with the limitations disclosed. A number cannot be "
        "improved by re-framing the measurement — only by fixing the "
        "model and measuring again.",
        tone="caution"))
    f.append(P(
        "That rule has cost this project several comfortable claims, and the "
        "retractions are kept in the record rather than quietly corrected. "
        "Three examples appear in this document: a weapon false-positive rate "
        "measured on tight crops was superseded by a worse figure measured on "
        "full frames (section 9.4); a glove accuracy claim resting on five "
        "recordings was replaced by a cross-validated one over 208 (section "
        "11.2); and a documented five-second cancellation window on the "
        "automatic alarm path was found not to exist (section 7.3)."))
    return f


def s2():
    f = H1("2", "The system in brief")

    f.append(H2("2.1&#160;&#160;The problem"))
    f.append(P(
        "An emergency application that requires its user to unlock a phone, "
        "find an app and press a button has already failed the situations that "
        "matter most. The hands are the first thing an assault occupies. "
        "SafeHer is built around a single requirement — <b>an alert gets "
        "out</b> — and every design decision in this document serves it.", "lead"))

    f.append(H2("2.2&#160;&#160;What the system does"))
    f.append(P(
        "Three independent sensing modalities watch for danger. A glove worn on "
        "the hand classifies motion. Glasses stream what the wearer sees to the "
        "phone, which looks for a weapon in the picture. The phone's microphone "
        "feeds a speech recogniser whose transcript is scored for distress "
        "language. Each modality produces a number between 0 and 1, several "
        "times a second."))
    f.append(FLOW([
        "<b>Sense</b><br/><font size=7>glove, camera, microphone</font>",
        "<b>Score</b><br/><font size=7>three independent models</font>",
        "<b>Fuse</b><br/><font size=7>one weighted engine</font>",
        "<b>Dispatch</b><br/><font size=7>contacts, evidence, record</font>",
    ]))
    f.append(P(
        "A single fusion engine combines whichever of the three reported into "
        "one score, smooths it, and compares it against the user's threshold. "
        "Crossing that threshold creates an incident record, notifies the "
        "user's emergency contacts in her own priority order, and starts "
        "recording evidence. A separate and deliberately simpler path lets the "
        "glove raise the alarm with no server involved at all."))
    f.append(P(
        "The novel engineering is not in any one of the three models — "
        "each is a conventional architecture. It is in the arbitration between "
        "them: how three unreliable, intermittent and unevenly trustworthy "
        "signals are combined into a decision that is willing to act on one "
        "certain sensor, refuses to be talked into acting by agreement alone, "
        "and treats a sensor that said nothing differently from a sensor that "
        "said ‘calm’. Section 6 is that mechanism."))

    f.append(H2("2.3&#160;&#160;Component inventory"))
    f.append(TBL(
        ["Component", "Technology", "Where it runs", "Status"],
        [
            ["Smart Glove", "ESP32-C3 + MPU-6500; XGBoost, 5 classes",
             "On the glove", "Trained, shipped, hardware-validated"],
            ["Smart Glasses", "XIAO ESP32-S3 Sense; MJPEG + PDM audio over WiFi",
             "On the glasses", "Streams; runs no model"],
            ["Weapon detector", "YOLOv8-nano, 2 classes, fp16 TFLite via LiteRT",
             "On the phone", "Trained, shipped, runs on hardware"],
            ["Voice distress", "TF-IDF (word + char n-grams) into logistic "
             "regression, pure Dart",
             "On the phone", "Trained, shipped"],
            ["Facial expression", "MobileNetV3-Small, fp16 ONNX",
             "On the backend", "Recorded as evidence; barred from scoring"],
            ["Fusion engine", "Weighted renormalised sum with floors, "
             "corroboration and EMA",
             "Backend", "Complete and unit-tested"],
            ["Mobile application", "Flutter / Dart, Riverpod, GoRouter",
             "Android and iOS", "1,193 tests passing"],
            ["Backend", "FastAPI, Python 3.12, SQLAlchemy + Alembic",
             "Server", "614 tests passing"],
        ],
        widths=[18, 32, 17, 33]))
    return f


def s3():
    f = H1("3", "Hardware")
    f.append(P(
        "Two wearables, built as prototypes rather than production assemblies. "
        "Each one's division of labour — whether it runs a model or only "
        "carries data — follows from what its silicon can actually do, and "
        "the two came out opposite.", "lead"))

    f.append(H2("3.1&#160;&#160;Smart Glove"))
    f.append(KV([
        ("Microcontroller", "ESP32-C3"),
        ("Inertial sensor", "MPU-6500 (accelerometer and gyroscope)"),
        ("Sampling", "100 Hz, 100-sample windows with 50-sample overlap, "
                     "one classification every 0.5 s"),
        ("Features", "51 per window, computed on the device"),
        ("Model", "XGBoost, 5 classes, 600 boosting rounds × 5 classes "
                  "= 3,000 trees, 37,176 nodes, compiled in as C arrays"),
        ("Classes", "FALL, SUDDEN_MOVEMENT, SHAKING, TWISTING, NORMAL"),
        ("Link", "Bluetooth Low Energy; notifies the phone with a "
                 "classification and a confidence, e.g. FALL,0.93"),
        ("Not implemented", "Heart rate and battery — the telemetry "
                            "characteristic sends zeros, and the application "
                            "reads a zero heart rate as ‘no sensor’ "
                            "rather than as a measurement"),
    ], label_w=24))
    f.append(SP(10))
    f.append(P(
        "The glove sends a <i>conclusion</i>, not telemetry. Inference finishes "
        "on the ESP32 and the result crosses BLE as about a dozen bytes. This "
        "is what makes the glove alarm path survive a dead backend, an unpaid "
        "data plan and a basement with no signal: nothing between the sensor "
        "and the alarm needs a network."))
    f.append(P(
        "The byte-level wire format is a contract between two codebases that "
        "cannot import each other. The application's parser is pinned by tests "
        "carrying the firmware's literal payload strings; the firmware half "
        "cannot be checked automatically, and that asymmetry is a known "
        "weakness rather than an oversight."))

    f.append(H2("3.2&#160;&#160;Smart Glasses"))
    f.append(KV([
        ("Board", "Seeed XIAO ESP32-S3 Sense (the plain S3 has no camera or "
                  "microphone)"),
        ("Camera", "OV series, JPEG encoded by the sensor"),
        ("Video", "MJPEG over HTTP, multipart/x-mixed-replace, one video client "
                  "at a time"),
        ("Microphone", "PDM over I2S, 16 kHz, 16-bit, mono"),
        ("Link", "WiFi, 2.4 GHz only — the S3 has no 5 GHz radio"),
        ("Discovery", "mDNS, safeher-glasses.local"),
        ("Endpoints", "GET /stream (video, consumed by the weapon detector); "
                      "GET /status (identity, firmware, battery, used for "
                      "pairing); GET /audio (streaming WAV, evidence only); "
                      "GET /level (loudness in dBFS, served but not yet polled)"),
    ], label_w=24))
    f.append(SP(10))
    f.append(P(
        "The glasses run no model. They capture and transmit; the phone scores "
        "and decides. Video never leaves the phone — only a number does."))
    f.append(NOTE(
        "One wire contract worth stating",
        "Every MJPEG part carries a Content-Length header, because the phone's "
        "parser uses it to find where a frame ends. A part without one is "
        "skipped, and a part claiming more than 2 MB is treated as a "
        "desynchronised stream and skipped too: an unbounded read on a corrupt "
        "length never recovers, and would eventually take the phone's memory "
        "with it."))

    f.append(H2("3.3&#160;&#160;Where each model runs, and why"))
    f.append(P(
        "The two devices are arranged in opposite ways, and the reason is "
        "arithmetic rather than preference. The glove's XGBoost model over 51 "
        "features fits in an ESP32-C3's flash and runs inside its 0.5 second "
        "budget. YOLOv8-nano at 640×640 needs roughly two orders of "
        "magnitude more compute and memory than an ESP32-S3 has. So the glove "
        "computes and reports a conclusion, while the glasses report raw frames "
        "and the phone computes."))
    f.append(TBL(
        ["", "Smart Glove", "Smart Glasses"],
        [
            ["Model location", "On the device", "On the phone"],
            ["What crosses the link", "A classification and a confidence",
             "JPEG frames"],
            ["Transport", "BLE", "WiFi / HTTP"],
            ["Works with no network", "Yes — end to end",
             "No — needs the phone on the same WiFi"],
            ["Privacy posture", "Nothing recorded on either side",
             "Frames stay on the phone; only a score leaves it"],
        ],
        widths=[24, 38, 38]))
    f.append(SP(10))

    f.append(H2("3.4&#160;&#160;The phone"))
    f.append(P(
        "The phone is not an accessory in this architecture; it is the gateway. "
        "It holds the two models that need real compute, runs the fusion client, "
        "keeps the alarm path alive in the background through an Android "
        "foreground service, and is the only component that talks to the "
        "backend. All measurements of inference speed in this document were "
        "taken on a Samsung SM-M166P (arm64-v8a, Android 15)."))
    return f


def s4():
    f = H1("4", "Software architecture")

    f.append(H2("4.1&#160;&#160;The three tiers"))
    f.append(TBL(
        ["Tier", "Responsibility"],
        [
            ["Firmware",
             "Sampling, windowing and — on the glove only — inference. "
             "The glove notifies over BLE; the glasses serve HTTP."],
            ["Mobile application",
             "The gateway. Pairs both devices, runs the weapon and voice models, "
             "runs the glove alarm vote, holds the countdown UI, captures "
             "evidence, queues work while offline, and is the only client of "
             "the backend."],
            ["Backend",
             "Authentication, the fusion engine, incident records, the contact "
             "fan-out, evidence references, the real-time WebSocket feed and "
             "push notification."],
        ],
        widths=[20, 80]))
    f.append(SP(10))

    f.append(H2("4.2&#160;&#160;The phone as gateway"))
    f.append(P(
        "The original design had both devices publish raw telemetry to an MQTT "
        "broker, with the server running every model. That is no longer how the "
        "system works, and the change is substantive rather than cosmetic: the "
        "glove runs its own model and sends a conclusion, and the glasses "
        "stream to the phone directly, so there is no raw telemetry stream left "
        "to publish. Events now reach the backend as authenticated requests "
        "from a user rather than as unattributed messages from a device. The "
        "MQTT ingestion path still exists in the backend but its worker "
        "defaults to off, and no current firmware publishes to it."))
    f.append(P(
        "Two properties follow from putting the gateway on the phone. Inference "
        "on raw video happens where the video already is, so frames never leave "
        "the device. And the device-to-alarm path no longer depends on a broker "
        "being reachable."))

    f.append(H2("4.3&#160;&#160;Storage"))
    f.append(TBL(
        ["Store", "Holds", "Written by"],
        [
            ["PostgreSQL (production) / SQLite (development)",
             "Users, incidents, devices, locations, media references, "
             "notification logs, push tokens, emergency contacts, safe "
             "journeys, hashed safety PINs",
             "The backend's repositories, through SQLAlchemy; schema owned by "
             "Alembic migrations"],
            ["Supabase private bucket",
             "Encrypted evidence recordings",
             "The mobile application; the provider holds ciphertext it cannot "
             "read"],
            ["Supabase events table",
             "An append-only archive of raw events, parallel to the "
             "transactional database and not a replacement for it",
             "The event processor only — the API service has no Supabase "
             "client at all"],
            ["On-device (Hive)",
             "Session state, onboarding flags, the offline action queue",
             "The mobile application"],
            ["BLE link",
             "Nothing. Transport only — classifications are consumed by "
             "the vote and discarded; only a resulting incident persists",
             "—"],
        ],
        widths=[22, 44, 34]))
    return f


def s5():
    f = H1("5", "The detection subsystems")
    f.append(P(
        "Three models produce the numbers the fusion engine arbitrates between, "
        "and a fourth is deliberately excluded from it. Each is described here "
        "by what it consumes, what it emits, and the gates its output must pass "
        "before it can influence anything.", "lead"))

    f.append(H2("5.1&#160;&#160;Motion — on the glove"))
    f.append(P(
        "The 51 window features go into the on-device XGBoost model, which "
        "emits one of five classes with a confidence. The firmware will not "
        "transmit a classification below its own confidence gate, and applies a "
        "debounce to repeated sudden-movement readings."))
    f.append(P(
        "The class does not reach the fusion engine directly. It is mapped to a "
        "threat weight first, and that mapping is a safety control in its own "
        "right:"))
    f.append(TBL(
        ["Class", "Weight", "Maximum score reachable", "Can alone reach the 0.75 trigger?"],
        [
            ["FALL", "1.00", "1.00", "Yes"],
            ["SUDDEN_MOVEMENT", "0.70", "0.70", "No — would need confidence above 1.07"],
            ["SHAKING", "0.30", "0.30", "No — would need confidence above 2.5"],
            ["TWISTING", "0.30", "0.30", "No"],
            ["NORMAL", "—", "—", "Withheld entirely — see section 6.3"],
        ],
        widths=[25, 12, 22, 41],
        aligns=["LEFT", "CENTER", "CENTER", "LEFT"]))
    f.append(SP(10))
    f.append(P(
        "The consequence is structural rather than statistical: of the glove's "
        "five classes, only a fall can reach the automatic trigger unaided, no "
        "matter how confident the classifier becomes. Section 11.3 measures "
        "what that is worth."))

    f.append(H2("5.2&#160;&#160;Weapon — on the phone"))
    f.append(KV([
        ("Architecture", "YOLOv8-nano, 2 classes (pistol, knife)"),
        ("Shipped artifact", "fp16 TFLite, 6,129,672 bytes, run through LiteRT "
                             "on the phone's GPU"),
        ("Input", "[1, 640, 640, 3] float32 NHWC; letterboxed to 640 with pad "
                  "value 114, divided by 255"),
        ("Output", "[1, 6, 8400] float32; boxes as centre-x, centre-y, width, "
                   "height normalised to 0..1"),
        ("Server fallback", "An int8 ONNX export of the same model, for web "
                            "clients with no on-device runtime"),
    ], label_w=24))
    f.append(SP(10))
    f.append(P(
        "A single detection is not a weapon signal. Detections below a "
        "confidence floor of 0.55 are discarded before scoring, and the "
        "survivors are voted over a sliding window of 15 frames:"))
    f.append(NOTE(
        "The weapon score",
        "<font name=\"Courier\">value = meanConfidence × (hits / window)"
        "</font><br/><br/>"
        "A single confident frame therefore scores about one fifteenth of its "
        "confidence. Persistence is required, which is what stops a reflection, "
        "a passing object or one bad frame from contributing meaningfully. The "
        "cost of that protection is latency, and it is accepted deliberately."))
    f.append(P(
        "The camera is not open by default, and the weapon detector cannot open "
        "it. The camera opens only on an audio score of at least 0.50 or a "
        "glove score of at least 0.70; a weapon detection can <i>extend</i> an "
        "already-open session but can never start one. This ordering exists so "
        "that a false weapon detection cannot bootstrap its own evidence."))

    f.append(H2("5.3&#160;&#160;Voice distress — on the phone"))
    f.append(KV([
        ("Architecture", "TF-IDF over word n-grams unioned with character "
                         "n-grams, into logistic regression; 7,611 features"),
        ("Implementation", "Pure Dart, 387,427 bytes of coefficients, byte-"
                           "identical to the training export"),
        ("Input", "The transcript from the platform speech recogniser. The "
                  "transcript is classified and discarded; no audio is sent "
                  "anywhere for this"),
        ("Classes", "distress, normal, threat"),
        ("Decision rule", "elevated = P(threat) + P(distress), elevated at or "
                          "above 0.50"),
    ], label_w=24))
    f.append(SP(10))
    f.append(P(
        "This replaced an earlier CNN and LSTM keyword spotter that scored "
        "below a fuzzy string match on real phrases. The replacement is "
        "deliberately unglamorous: it is small enough to run in Dart with no "
        "native runtime, it is fully inspectable, and it reproduces its "
        "training figures exactly from the shipped bytes."))

    f.append(H2("5.4&#160;&#160;Facial expression — recorded, never scored"))
    f.append(P(
        "A MobileNetV3-Small expression classifier runs on the backend over "
        "frames the phone has already uploaded. It is attached to the incident "
        "record and <b>cannot reach the threat score</b>. That exclusion is "
        "enforced structurally, not by convention: the fusion engine's input "
        "type has exactly three fields and accepts nothing else, and a test "
        "fails if that shape changes."))
    f.append(P(
        "The reason is its own measurements. Its <i>fear</i> class — the "
        "only one with any safety relevance — is recorded at 47 per cent "
        "recall, which is close to a coin toss, and those figures are the "
        "training run's own and have never been independently re-measured. "
        "Someone will eventually notice that fear was on the user's face and "
        "reach for a small additive bonus. It would look like care, and it "
        "would mean alarms during ordinary life."))
    return f


def s6():
    f = H1("6", "Threat fusion")
    f.append(P(
        "One engine decides whether SafeHer raises an alarm by itself. There is "
        "no second scorer — not in the application, not in a cloud "
        "function. The interface displays what the engine returns and never "
        "recomputes it. This section is the mechanism in full, because it is "
        "the part of the system that is genuinely designed rather than "
        "assembled.", "lead"))

    f.append(H2("6.1&#160;&#160;The weights"))
    f.append(TBL(
        ["Signal", "Weight", "Rationale"],
        [
            ["Weapon", "0.40",
             "The most specific evidence: a knife in view has few innocent "
             "readings."],
            ["Voice", "0.35",
             "Specific when correct, but the measured specificity on realistic "
             "audio is the weakest link in the system."],
            ["Motion", "0.25",
             "The most reliable producer and the only one that works with no "
             "network, but the least specific — a fall is not necessarily "
             "an assault."],
        ],
        widths=[16, 12, 72],
        aligns=["LEFT", "CENTER", "LEFT"]))
    f.append(SP(10))
    f.append(P(
        "The weights are only the starting point. Five further mechanisms act "
        "on the result, and each exists because the weighted mean alone gets a "
        "specific case wrong."))

    f.append(H2("6.2&#160;&#160;Six mechanisms"))

    f.append(H3("Renormalisation over reporting signals"))
    f.append(P(
        "The weighted sum is divided by the total weight of the signals that "
        "<i>actually reported</i>, not by 1.0. A sensor that is absent cannot "
        "hold the score down. Without this, a woman with no glasses paired "
        "could never exceed 0.60 however loudly she shouted, because the "
        "weapon signal's 0.40 would sit in the denominator contributing "
        "nothing."))

    f.append(H3("A solo-signal floor"))
    f.append(P(
        "The score never falls below 0.50 times the strongest single reading. A "
        "weighted mean asks how alarming the situation is on average, which is "
        "the wrong question when one sensor is certain and the others have "
        "nothing to say. A knife in view is not made safe by a calm wrist. At "
        "0.50, one maximal signal alone reaches 0.50 — enough to raise the "
        "displayed level and start watching, and nowhere near the 0.75 default "
        "trigger."))

    f.append(H3("A corroboration bonus"))
    f.append(P(
        "Each additional signal independently above 0.50 adds 0.05. Two sensors "
        "on different limbs watching different things, both alarmed, is "
        "stronger evidence than one shouting — and a weighted sum cannot "
        "express that, because a lone glove at 0.9 and a glove at 0.9 beside a "
        "weapon at 0.9 differ only by the weapon's weight. The bonus is "
        "deliberately capped so that corroboration alone can never lift a score "
        "across a band boundary."))

    f.append(H3("Exponential smoothing, with an expiry"))
    f.append(P(
        "The reported score is <font name=\"Courier\">0.30 × raw(t) + 0.70 "
        "× smoothed(t-1)</font>. A first reading is taken as-is "
        "rather than smoothed against zero, because seeding at zero would halve "
        "a genuine spike — the one sample most likely to be the emergency. "
        "That protection only works if ‘first’ means first of this "
        "episode, so a stored previous value expires after 30 seconds. Before "
        "that expiry existed, a score left over from a previous session could "
        "be smoothed against days later: a stale previous of 0.70 turns a "
        "genuine spike of 0.80 into 0.73, which is below the 0.75 threshold, so "
        "the alarm that should have fired on the first sample did not fire at "
        "all."))

    f.append(H3("Bands with hysteresis"))
    f.append(P(
        "The score is banded SAFE / ELEVATED (0.30) / HIGH (0.60) / CRITICAL "
        "(0.80), and must fall 0.05 below a band's floor before dropping out of "
        "it. Without the margin, a score hovering at a boundary flaps between "
        "levels every heartbeat, which reads to a user as the application "
        "panicking and calming down twice a second."))

    f.append(H3("A de-duplication window"))
    f.append(P(
        "Once an alert fires, a second one is suppressed for 120 seconds. The "
        "specification is internally inconsistent here — one section says "
        "120 seconds and two others say 60 — and the longer reading was "
        "taken deliberately: a suppressed duplicate is a nuisance, while a "
        "second dispatch spams every contact of a woman already in an "
        "emergency."))

    f.append(H2("6.3&#160;&#160;Absent is not zero"))
    f.append(NOTE(
        "The invariant",
        "A sensor that did not report is <b>omitted</b> from the fusion. It is "
        "never passed as 0.0, because 0.0 is a claim: it says a sensor looked "
        "and saw calm. An omission says only that nothing was heard from it, "
        "and renormalisation then redistributes its weight to the signals that "
        "did report.",
        tone="caution"))
    f.append(P(
        "This invariant reaches further than the fusion engine. When the glove "
        "classifies a window as NORMAL the pipeline actively <i>withdraws</i> "
        "the glove signal rather than reporting a low score, because a reported "
        "0.0 would carry the glove's full 0.25 weight and drag a genuine weapon "
        "or voice reading down. The same rule governs the user interface: a "
        "preview showing no detection boxes now distinguishes "
        "‘watching — no weapon detected’ from ‘no video has "
        "reached the detector, so nothing has been examined’. Those two "
        "states looked identical on screen until 4 November 2026, and the "
        "difference cost a full hardware session."))

    f.append(H2("6.4&#160;&#160;A worked example"))
    f.append(P(
        "A glove reporting FALL at 0.93 and nothing else, on a phone with no "
        "glasses paired and a silent microphone:"))
    f.append(TBL(
        ["Step", "Computation", "Result"],
        [
            ["Signals reporting", "glove only; weapon and audio omitted", "—"],
            ["Glove score", "0.93 confidence × 1.00 FALL weight", "0.930"],
            ["Weighted sum", "0.25 × 0.930", "0.2325"],
            ["Renormalise", "0.2325 ÷ 0.25 (the only reporting weight)", "0.930"],
            ["Solo floor", "0.50 × 0.930 = 0.465, below the current value",
             "no effect"],
            ["Corroboration", "one signal reporting, so no bonus", "no effect"],
            ["Smoothing", "first reading of the episode, taken as-is", "0.930"],
            ["Against threshold", "0.930 against 0.75", "<b>trigger</b>"],
        ],
        widths=[22, 54, 24],
        aligns=["LEFT", "LEFT", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "The arithmetic makes an important property visible: with one signal "
        "reporting, the weight cancels entirely and the fused score <i>is</i> "
        "that signal's score. The weights only matter when more than one sensor "
        "speaks. This is also the mechanism behind the exposure measured in "
        "section 11.3 — a single confirmed false fall posts its own "
        "confidence as the fused score, and two of the three recordings where "
        "that happened exceeded 0.95."))
    return f


def part_a():
    out = []
    out += cover()
    out.append(PageBreak())
    out += contents()
    out.append(PageBreak())
    for fn in (s1, s2, s3, s4, s5, s6):
        out += fn()
    return out
