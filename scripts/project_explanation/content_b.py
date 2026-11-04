"""Sections 7-15."""

import os

from PIL import Image as PILImage
from reportlab.lib.units import mm
from reportlab.platypus import PageBreak, Paragraph, Spacer

from blocks import BULLETS, FIG, FLOW, H1, H2, H3, KV, NOTE, NUMBERED, P, SP, TBL
from style import S

FIGDIR = "docs/assets/evaluation"
GAP = "&#160;&#160;"
_HERE = os.path.dirname(os.path.abspath(__file__))


def _side_by_side(left, right, out_name, height=620, gap=26):
    """Compose two annotated detections into one figure, on white."""
    ims = []
    for p in (left, right):
        im = PILImage.open(p).convert("RGB")
        w, h = im.size
        ims.append(im.resize((max(1, round(w * height / h)), height),
                             PILImage.LANCZOS))
    total = sum(i.width for i in ims) + gap
    canvas = PILImage.new("RGB", (total, height), "white")
    x = 0
    for im in ims:
        canvas.paste(im, (x, 0))
        x += im.width + gap
    out = os.path.join(_HERE, out_name)
    canvas.save(out)
    return out


def s7():
    f = H1("7", "The two alarm paths")
    f.append(P(
        "SafeHer can raise an alarm two ways, and they share almost nothing. "
        "That redundancy is deliberate: the paths fail for different reasons, "
        "so a failure in one does not disable the other.", "lead"))

    f.append(H2(f"7.1{GAP}Path one: the glove, with no server in the loop"))
    f.append(FLOW([
        "<b>Glove</b><br/><font size=7>XGBoost on the ESP32</font>",
        "<b>BLE</b><br/><font size=7>FALL,0.93</font>",
        "<b>Vote</b><br/><font size=7>2 falls in 5 s</font>",
        "<b>Countdown</b><br/><font size=7>cancellable</font>",
        "<b>Dispatch</b><br/><font size=7>same route as manual SOS</font>",
    ]))
    f.append(P(
        "Inference runs on the glove and the conclusion reaches the phone over "
        "BLE. A dead backend, no mobile signal, and an untrained server-side "
        "model all leave this path working. Four properties of it are "
        "deliberate:"))
    f.append(BULLETS([
        "<b>Two readings, not one.</b> The alarm needs two qualifying FALL "
        "classifications inside five seconds, each above the user's confidence "
        "threshold. One alone is a glove dropped on a table.",
        "<b>The vote does not live in a widget.</b> Flutter stops pumping "
        "frames when the application leaves the screen, so anything decided "
        "inside a build method silently stops running when the phone is "
        "pocketed, which is the exact case the glove exists for. The vote runs "
        "in a keep-alive provider, and its tests run against a bare container "
        "with no widget tree at all.",
        "<b>A foreground service holds the process open.</b> Android freezes a "
        "backgrounded application and stops delivering BLE callbacks. The "
        "service runs only while a glove is actually connected, and reports "
        "whether it is <i>genuinely</i> running — notification permission "
        "can be denied and manufacturers kill background work. The interface "
        "tells a user she can pocket her phone only when the platform confirms "
        "the service started.",
        "<b>It opens a countdown; it never dispatches.</b> An automatic trigger "
        "must not be faster, quieter or harder to stop than one the user asked "
        "for, so it lands on the same screen a manual SOS does. When the "
        "application is backgrounded the countdown is routed to first and the "
        "screen woken second, so the countdown is already up when the activity "
        "arrives rather than racing it.",
    ]))

    f.append(H2(f"7.2{GAP}Path two: fused scores, decided on the server"))
    f.append(FLOW([
        "<b>Three signals</b><br/><font size=7>posted at 1 Hz</font>",
        "<b>Fusion</b><br/><font size=7>section 6</font>",
        "<b>Incident</b><br/><font size=7>created with its reasons</font>",
        "<b>Fan-out</b><br/><font size=7>contacts in priority order</font>",
    ]))
    f.append(P(
        "The phone batches whichever signals reported and posts them about once "
        "a second. When the smoothed score crosses the user's threshold the "
        "backend creates an incident carrying every per-modality score, the "
        "weapon confidence, the fused value and the threshold it was compared "
        "against, then notifies up to ten emergency contacts in the user's own "
        "priority order, each attempted independently over SMS, then email, "
        "then push, three attempts per channel."))
    f.append(P(
        "Every automatic incident records <i>why</i> it fired, turned into a "
        "plain sentence — <i>“Sudden, violent movement was detected. "
        "A knife was detected in view.”</i> A weapon below the naming "
        "floor is deliberately not named, and an absent sensor is stated as "
        "absent rather than rendered as having seen nothing."))

    f.append(H2(f"7.3{GAP}Three disclosed asymmetries between the paths"))
    f.append(NOTE(
        "There is no cancellation window on the automatic path",
        [
            "Project documentation previously stated that a five-second "
            "cancellable countdown stood between an automatic trigger and "
            "dispatch. It does not. That countdown gates the <b>manual</b> and "
            "shake-initiated SOS only. A server-side automatic dispatch "
            "notifies contacts the instant the threshold is crossed.",
            "This was recorded as a decision rather than quietly fixed: the "
            "exposure is accepted, because a delay on the automatic path is a "
            "delay in exactly the case where the user may be unable to act. "
            "What was built instead is <b>post-dispatch retraction</b>, which "
            "makes a false automatic alarm recoverable — the alert still "
            "leaves immediately, and a correction follows to the contacts it "
            "reached. Retracting during the first seconds stops the fan-out "
            "rather than racing it.",
        ],
        tone="caution"))
    f.append(P(
        "<b>Evidence capture is wired to path one only.</b> The glove path "
        "navigates through the emergency screen, which starts the evidence "
        "recorder. The server-side fusion path creates the incident and "
        "notifies contacts but starts no recorder, because by the time the "
        "phone learns of the dispatch the server has already made it. Wiring "
        "the second path through the same navigation would re-enter the "
        "dispatch flow and notify real contacts twice, so it has been left "
        "unwired pending a dedicated ‘record for an already-dispatched "
        "incident’ mode. This is a known gap, stated here rather than "
        "implied away."))
    f.append(P(
        "<b>Building the retraction surfaced a defect in the fan-out itself.</b> "
        "An emergency contact who was also a SafeHer user raised an unhandled "
        "name error in the push branch, which escaped a function documented as "
        "never raising and aborted the fan-out in priority order — so that "
        "contact, and everyone the user had ranked below them, were never "
        "notified. It is recorded in the evaluation data as the most serious "
        "integration defect found."))
    return f


def s8():
    f = H1("8", "Evidence capture and chain of custody")
    f.append(P(
        "An alert that arrives with nothing attached asks a contact to act on "
        "trust. Evidence capture exists so that the recording covers the part "
        "that matters, and so that what is stored cannot be read by the people "
        "storing it.", "lead"))

    f.append(H2(f"8.1{GAP}Recording starts with the countdown, not after dispatch"))
    f.append(P(
        "Audio — and video when the camera can open — begins the "
        "moment the countdown appears, not when the alert is sent. The seconds "
        "a user spends deciding whether to cancel are the seconds most likely "
        "to contain the thing worth recording, and a recorder started after "
        "dispatch misses all of them."))

    f.append(H2(f"8.2{GAP}Encryption at rest"))
    f.append(KV([
        ("Cipher", "AES-256-GCM, applied before the file touches any "
                   "filesystem or storage provider"),
        ("Nonce", "12 bytes, generated per file and stored as a prefix on the "
                  "ciphertext — a nonce is not secret, only single-use"),
        ("Where it lives", "A private Supabase bucket, or local blob storage. "
                           "The provider holds ciphertext it cannot read"),
        ("Retrieval", "Through an authenticated, ownership-checked endpoint "
                      "only. Nothing is served from a public bucket or a "
                      "guessable path, so a leaked link is not enough to view "
                      "a recording"),
    ], label_w=22))
    f.append(SP(10))

    f.append(H2(f"8.3{GAP}Chain of custody"))
    f.append(P(
        "An incident exports as a forensic PDF carrying a SHA-256 digest per "
        "recording and a digest over the full incident record, so a report can "
        "be checked against the evidence it describes. Sharing is time-limited "
        "and revocable: a share link expires after seven days, can be withdrawn "
        "at any point, and streams evidence per request rather than handing out "
        "a durable object URL."))
    f.append(P(
        "Alongside this the system supports a full data export and account "
        "deletion with a thirty-day grace period, which are statutory rather "
        "than discretionary features."))
    return f


def s9():
    f = H1("9", "Measured results: weapon detection")

    f.append(H2(f"9.1{GAP}The test set"))
    f.append(KV([
        ("Images", "658, held out by image from a 70/20/10 split with a fixed "
                   "seed, over a merged corpus of 7,539 images"),
        ("Instances", "783 — 433 pistol, 350 knife. Counts were "
                      "reconciled against the label files exactly, which "
                      "validates the ground-truth parsing"),
        ("Sources", "Open Images V7 (annotations CC BY 4.0, images CC BY 2.0) "
                    "and OD-WeaponDetection, Universidad de Granada"),
        ("Matching", "IoU 0.5"),
        ("Verification", "Artifact SHA-256 checked before measuring, so the "
                         "bytes measured are the bytes that ship"),
    ], label_w=18))
    f.append(SP(10))

    f.append(H2(f"9.2{GAP}Benchmark accuracy"))
    f.append(P(
        "Measured with the reference validator on the locked test split, at "
        "640 pixels, batch size 1:"))
    f.append(TBL(
        ["Artifact", "mAP@0.5", "mAP@0.5:0.95", "Pistol AP", "Knife AP",
         "Reproduces its recorded figure to"],
        [
            ["Phone, fp16 TFLite (shipped)", "<b>0.9068</b>", "0.6317",
             "0.9316", "0.8820", "0.0012"],
            ["Server, int8 ONNX (shipped)", "<b>0.9023</b>", "0.6269",
             "0.9264", "0.8781", "0.0010"],
            ["Six-class candidate (not shipped)", "0.8938", "0.6260",
             "0.9313", "0.8563", "—"],
        ],
        widths=[27, 11, 14, 11, 11, 26],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "Quantisation cost nothing measurable. The fp16 phone artifact is "
        "marginally the stronger of the two."))

    f.append(FIG(f"{FIGDIR}/precision_recall_curve.png", "Figure 1",
                 "Precision-recall per class for the shipped detector over all "
                 "658 test images and 783 instances. Not a selected sample.",
                 max_h=86 * mm))

    f.append(H2(f"9.3{GAP}What the application actually operates at"))
    f.append(NOTE(
        "A distinction that must not be collapsed",
        "mAP@0.5 integrates precision over the whole recall curve, including "
        "detections below the confidence floor that the application discards "
        "before they can reach the weapon signal. <b>The application does not "
        "operate at 0.9068.</b> At its deployed floor of 0.55 it runs at "
        "precision 0.9234 and recall 0.8077. Both figures are recorded, and the "
        "sentence ‘the weapon detector achieves 0.9068’ must never "
        "sit next to a claim about what the application does."))
    f.append(TBL(
        ["Confidence floor", "Precision", "Recall", "F1", "Pistol P / R",
         "Knife P / R"],
        [
            ["0.35", "0.8978", "0.8531", "0.8749", "0.9422 / 0.8661",
             "0.8468 / 0.8371"],
            ["0.45", "0.9169", "0.8314", "0.8721", "0.9529 / 0.8406",
             "0.8750 / 0.8200"],
            ["<b>0.55 (deployed)</b>", "<b>0.9320</b>", "<b>0.8046</b>",
             "<b>0.8636</b>", "0.9673 / 0.8199", "0.8900 / 0.7857"],
            ["0.65", "0.9429", "0.7586", "0.8408", "0.9742 / 0.7852",
             "0.9039 / 0.7257"],
        ],
        widths=[20, 14, 12, 12, 21, 21],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(12))

    f.append(H2(f"9.4{GAP}The false-positive finding"))
    f.append(P(
        "Accuracy on a test split says what the model does when a weapon is "
        "present. It says nothing about what it does the rest of the time, and "
        "the rest of the time is almost all of the time. Every one of the 7,539 "
        "images in the weapon dataset contains a weapon: the model has never "
        "been trained on a frame where the correct answer is ‘nothing "
        "here’."))
    f.append(P(
        "To measure that, 2,072 real full frames were selected from the same "
        "source dataset's detection set — frames carrying a hand-held "
        "object and annotated as containing no pistol and no knife. None of the "
        "2,072 appears in any training split, checked by filename stem and by "
        "embedded name."))
    f.append(TBL(
        ["Object in frame", "Frames", "Frames producing a weapon detection "
         "at 0.55", "Rate"],
        [
            ["Wallet or purse", "601", "182", "<b>30.3%</b>"],
            ["Smartphone", "715", "131", "18.3%"],
            ["Banknote", "477", "68", "14.3%"],
            ["Card", "279", "40", "14.3%"],
            ["<b>All weapon-free frames</b>", "<b>2,072</b>", "<b>421</b>",
             "<b>20.3%</b>"],
        ],
        widths=[30, 14, 40, 16],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "A purse in the hand reads as a weapon in nearly a third of real "
        "frames. The worst single case scored a wallet as a pistol at 0.895. "
        "Raising the floor does not solve it: 0.75 cuts the rate to 5.7 per "
        "cent but drops recall to 0.6616, which is the wrong trade for a safety "
        "feature. The mitigation that does work is in the window vote of "
        "section 5.2 — 79.7 per cent of these frames never reached the "
        "floor at all, so persistence over fifteen frames suppresses most of "
        "them — and in the camera-activation ordering, which prevents a "
        "weapon detection from opening the camera that would feed it."))
    f.append(NOTE(
        "A correction kept in the record",
        "An earlier measurement of this ran on tight crops rather than full "
        "frames, and carried an explicit caveat guessing that real frames would "
        "be ‘probably lower’. That guess was wrong, and wrong in the "
        "direction that matters: the real rate is 20.3 per cent against the "
        "crop figure's 14.6 per cent. The caveat was right to exist and wrong "
        "in direction. The crop figure has been superseded, not averaged in.",
        tone="caution"))

    f.append(H2(f"9.5{GAP}Remediation: two retraining attempts, one rejected"))
    f.append(P(
        "The diagnosed cause was the absence of background images — frames "
        "with empty label files — from training. Two candidates were "
        "trained and measured against the shipped model. Neither has been "
        "shipped."))
    f.append(TBL(
        ["Measured at the 0.55 floor", "Shipped (in the application)",
         "Two-class + background", "Six-class candidate"],
        [
            ["False-positive rate on 1,385 held-out negatives", "20.6%",
             "4.7%", "<b>2.5%</b>"],
            ["Overall precision", "<b>0.9320</b>", "0.8230", "0.9278"],
            ["Overall recall", "<b>0.8046</b>", "0.7778", "<b>0.8046</b>"],
            ["Knife precision", "<b>0.8900</b>", "0.6898", "0.8893"],
            ["Verdict", "In the application",
             "<font color=\"#A33A28\"><b>Rejected</b></font>",
             "<font color=\"#2E6E4E\"><b>Strong candidate</b></font>"],
        ],
        widths=[34, 22, 22, 22],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "The first attempt confirmed the diagnosis and failed as a product: the "
        "false-positive rate fell 4.4-fold, but knife precision collapsed from "
        "0.890 to 0.690. The mechanism is visible in the data — the "
        "background frames are smartphones, wallets, banknotes and cards, which "
        "are flat, hand-held, elongated objects, and so is a knife. Suppressing "
        "them eroded the boundary that separates a blade from a phone."))
    f.append(P(
        "The second attempt tested that hypothesis directly by giving the four "
        "distractors their own classes rather than labelling them as "
        "background. It recovered knife precision almost exactly to the shipped "
        "figure while cutting the false-positive rate 8.1-fold, and held recall "
        "identical to four decimal places. It narrowly missed two of its three "
        "pre-registered targets — knife precision by 0.0007 and the "
        "false-positive target by 0.5 points — and it has not been "
        "shipped. What stands between it and shipping is a decision and a "
        "device test, not an open technical question."))
    f.append(NOTE(
        "Why the targets were written before the run",
        "Both runs had their pass conditions recorded in advance, which is what "
        "makes ‘narrowly missed’ a finding rather than a judgement "
        "call made after seeing the numbers. The six-class candidate is "
        "described as a strong candidate and not as a pass."))
    return f


def s10():
    f = H1("10", "Measured results: voice distress")

    f.append(H2(f"10.1{GAP}The test set and the two conditions"))
    f.append(P(
        "714 clips, held out <b>by phrase rather than by clip</b>, so every "
        "voice saying a given phrase falls on the same side of the split. "
        "Splitting by clip would place the same sentence in training and test "
        "and report a fantasy. Two conditions are measured: the transcript as a "
        "clean recogniser returns it, and a realistically degraded transcript."))
    f.append(TBL(
        ["Condition", "Accuracy", "Recall", "Precision", "Specificity",
         "Elevated F1", "Missed", "False alarms"],
        [
            ["Clean transcripts", "0.9202", "0.9675", "0.9141", "0.8333",
             "<b>0.9401</b>", "15 / 462", "42 / 252"],
            ["<b>Degraded (realistic)</b>", "0.8305", "0.8831", "0.8589",
             "<b>0.7341</b>", "0.8709", "54 / 462", "67 / 252"],
        ],
        widths=[21, 11, 10, 11, 12, 12, 11, 12],
        aligns=["LEFT"] + ["CENTER"] * 7))
    f.append(SP(10))
    f.append(P(
        "The degraded figure is the one to plan around. Both reproduce the "
        "published training figures exactly from the shipped bytes, which "
        "confirms the Dart export is lossless and that the measured model is "
        "the deployed one."))

    f.append(H2(f"10.2{GAP}The weakest number in the system"))
    f.append(P(
        "Specificity of 0.7341 means roughly one ordinary sentence in four "
        "reads as elevated. This matters beyond its own modality, because an "
        "audio score of 0.50 is what opens the camera: a false elevation here "
        "is what makes the weapon false-positive path of section 9.4 reachable "
        "at all."))
    f.append(P(
        "A second finding compounds it. Gibberish scores above the camera "
        "trigger — the nonsense string <font name=\"Courier\">zxqv "
        "blorptang mimsy</font> yields an elevated score of 0.594. The "
        "character n-gram vectoriser produces signal from unseen character "
        "patterns, which is precisely what a noisy recogniser emits."))

    f.append(H2(f"10.3{GAP}The threshold cannot fix it"))
    f.append(P(
        "The decision threshold is a constant in three places, so moving it "
        "would be the cheap fix. It was swept across the full range on the "
        "degraded condition, against a target of specificity at least 0.85 "
        "while holding recall at least 0.80."))
    f.append(FIG(f"{FIGDIR}/audio_threshold_sweep.png", "Figure 2",
                 "Recall against specificity across the decision threshold, on "
                 "all 714 held-out clips in the degraded condition. No "
                 "threshold satisfies both targets at once.",
                 max_h=80 * mm))
    f.append(P(
        "<b>No threshold satisfies both.</b> The lowest threshold reaching 0.85 "
        "specificity is 0.70, and it costs recall 0.7511 — missing 115 "
        "elevated clips to avoid 35 false alarms, which is the wrong trade for "
        "a safety feature. Peak accuracy sits at the deployed 0.50, so the "
        "existing constant is well chosen; accuracy is simply the wrong "
        "objective, being dominated by the 462 elevated clips against 252 "
        "normal ones. The corpus is the cause, not the constant."))

    f.append(H2(f"10.4{GAP}Root cause, and a rejected fix"))
    f.append(P(
        "The written training corpus ran about 226 elevated phrases to 128 "
        "normal ones. ‘Normal’ means everything a person might say "
        "that is not an emergency — almost everything anyone ever says "
        "— and it had the smallest share. Real speech is overwhelmingly "
        "ordinary; the training prior was the opposite."))
    f.append(P(
        "146 further normal phrases were added and the classifier retrained. "
        "The candidate gained 7.9 points of specificity and 0.5 of accuracy, "
        "and lost 3.7 points of recall:"))
    f.append(TBL(
        ["Degraded condition", "Accuracy", "Recall", "Specificity"],
        [
            ["Shipped in the application", "0.8305", "<b>0.8831</b>", "0.7341"],
            ["Rebalanced candidate", "0.8350", "0.8460", "<b>0.8130</b>"],
        ],
        widths=[40, 20, 20, 20],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "<b>Rejected.</b> The training script states its ship gate in its own "
        "documentation: ship only on an improvement in <i>both</i> accuracy and "
        "recall. Recall fell, so the gate refuses it, and the trade was not "
        "overridden. On a safety feature, 3.7 points of recall is seventeen "
        "more missed calls for help per 462, against 20 fewer false alarms per "
        "252. The trade is recorded so the decision can be revisited with "
        "better evidence rather than re-argued from memory."))
    f.append(NOTE(
        "The caveat that limits every figure in this section",
        [
            "The corpus is <b>synthetic speech</b> — neural text-to-speech "
            "voices, transcribed by a recogniser, plus degraded variants. "
            "Nobody in it is genuinely frightened. Recording real distress "
            "speech was deliberately descoped; no public dataset supplies it.",
            "These figures therefore describe the classifier on clean "
            "synthesised phrasings and their degraded variants, <b>not on a "
            "frightened human voice</b>. A second limit compounds it: the "
            "specificity figure rests on only 18 distinct held-out normal "
            "phrases (252 clips being 18 phrases across 14 voices). One of "
            "them, ‘Can you help me with this’, is a benign sentence "
            "containing a distress trigger — so the failure mode is real "
            "rather than hypothetical, but 18 phrases is a narrow basis for a "
            "claim about ordinary speech.",
        ],
        tone="caution"))
    return f


def s11():
    f = H1("11", "Measured results: motion")

    f.append(H2(f"11.1{GAP}Four gates, and what each one costs"))
    f.append(P(
        "The glove's raw classifier output is not the alarm. Four gates stand "
        "between them, and each one ships: the model's own argmax, a firmware "
        "confidence gate, a firmware debounce on repeated sudden movement, and "
        "the application's three-hit confirmation. Measuring the cascade stage "
        "by stage shows what each buys and what it costs."))
    f.append(FIG(f"{FIGDIR}/glove_gate_cascade.png", "Figure 3",
                 "Each shipped gate's effect on the per-window false-positive "
                 "rate and on fall recall. Measured over 431 windows.",
                 max_h=80 * mm))
    f.append(TBL(
        ["Stage", "False positives per normal window", "Fall recall per window"],
        [
            ["Raw model output", "13.5%", "75.8%"],
            ["+ firmware confidence gate", "7.4%", "65.3%"],
            ["+ firmware debounce", "5.4%", "65.3%"],
            ["+ application confirmation", "<b>2.0%</b>", "<b>55.8%</b>"],
        ],
        widths=[40, 32, 28],
        aligns=["LEFT", "CENTER", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "The cascade cuts false positives by a factor of about seven and costs "
        "twenty points of per-window recall. That trade is only acceptable "
        "because a fall is not a single window: the next measurement asks the "
        "question that matters."))

    f.append(H2(f"11.2{GAP}Per-event detection, cross-validated"))
    f.append(P(
        "The locked test split holds 5 fall and 7 normal recordings, which "
        "cannot support a claim about anything. 208 further recordings already "
        "existed in the dataset as training material and had never been scored "
        "as evaluation. Recording-level cross-validation makes them usable: "
        "every recording receives a prediction from a model that never saw it."))
    f.append(KV([
        ("Protocol", "Stratified group 5-fold cross-validation, grouped by "
                     "recording, fixed seed; the locked 22 recordings excluded "
                     "from every fold and never touched"),
        ("Why grouped", "Windows overlap by 50 of 100 samples. A random window "
                        "split would place near-identical windows from one "
                        "recording on both sides of a fold and report a "
                        "fantasy. Grouping by recording is what makes the "
                        "estimate honest"),
        ("Scale", "208 recordings, 3,585 windows — seven times the fall "
                  "evidence and nine times the normal evidence of the locked "
                  "split"),
        ("Gates applied", "All four, exactly as they ship"),
    ], label_w=20))
    f.append(SP(10))
    f.append(TBL(
        ["Measure", "Result", "95% confidence interval", "n"],
        [
            ["Fall detection", "<b>94.3%</b> (33 of 35)", "81.4% to 98.4%",
             "35 recordings"],
            ["Normal-activity false alarm", "14.3% (9 of 63)",
             "7.7% to 25.0%", "63 recordings"],
            ["Gated per-window false positives", "1.7%", "—",
             "1,209 windows"],
        ],
        widths=[32, 24, 26, 18],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(10))
    f.append(P(
        "The locked split gave 5 of 5 falls and 1 of 7 normals alarming — "
        "the same 14.3 per cent point estimate measured here independently, and "
        "the window false-positive rates agree too (2.0 per cent locked against "
        "1.7 per cent cross-validated). Two near-independent estimates landing "
        "together is stronger evidence than either alone."))
    f.append(NOTE(
        "What cross-validation does not fix",
        "These 208 recordings are one data-collection campaign. "
        "Cross-validation removes the sample-size objection; it does not remove "
        "the diversity objection. It cannot stand in for falls recorded by "
        "different people, on different floors, with different glove fits. That "
        "remains a disclosure item and a recording session."))

    f.append(H2(f"11.3{GAP}Can a false fall alone trigger an alert?"))
    f.append(P(
        "14.3 per cent of normal-activity recordings raise at least one fully "
        "confirmed glove alert. The question that decides whether that matters "
        "is whether such an alert, with nothing corroborating it, reaches the "
        "0.75 trigger. The answer is <b>yes, in 3 of 63 normal recordings "
        "— a 4.8 per cent exposure rate (95 per cent CI 1.6 to 13.1)</b>."))
    f.append(P(
        "Section 6.4 explains the mechanism. With one signal reporting, the "
        "weight cancels and the fused score <i>is</i> the glove score; the "
        "first posted reading is taken as-is rather than smoothed; and on a "
        "normal window the pipeline withdraws the glove signal entirely, so the "
        "calm windows between false hits do not decay the smoothed value, they "
        "freeze it. The worst case is therefore not a slow climb but a single "
        "confirmed reading posting its own confidence — which for two of "
        "the three recordings exceeded 0.95."))
    f.append(NOTE(
        "The structural protection that limits it",
        "Of the nine recordings that false-alarm, only three can reach the "
        "trigger unaided, and all three carry a FALL label. The other six carry "
        "only SUDDEN_MOVEMENT, SHAKING or TWISTING, whose class weights (0.70 "
        "and 0.30) make the threshold arithmetically unreachable no matter how "
        "confident the classifier becomes — they would need confidences of "
        "1.07 and 2.5 respectively. Measured, those six peak at 0.676, 0.609, "
        "0.275, 0.267 and 0.189, all below 0.75. The class-weight mapping of "
        "section 5.1 is doing real work."))
    f.append(P(
        "This figure is graded <b>derived</b>, not measured: no alert was "
        "dispatched to produce it. It is arithmetic over measured classifier "
        "outputs, using the system's own constants."))
    return f


def s12():
    f = H1("12", "Conformance against the specification's own targets")
    f.append(P(
        "The project's requirements specification fixes numeric targets for "
        "each model and for the system as a whole. Two of those metrics had "
        "never been computed from the shipped bytes — the specification "
        "states the weapon detector in mAP@0.5 and the voice path in F1, while "
        "the evaluation had reported the detector at its operating point and "
        "the classifier with no F1 at all. Both were computed and are reported "
        "here in the metric the specification names.", "lead"))
    f.append(FIG(f"{FIGDIR}/benchmark_conformance.png", "Figure 4",
                 "All six model and condition pairs against the targets written "
                 "for them. Measured from the shipped artifacts, with hashes "
                 "verified first.", max_h=76 * mm))
    f.append(TBL(
        ["Target", "Stated", "Measured", "Verdict"],
        [
            ["Weapon detector, mAP@0.5 (phone fp16)", "> 0.88", "0.9068",
             "<font color=\"#2E6E4E\"><b>MET</b></font>"],
            ["Weapon detector, mAP@0.5 (server int8)", "> 0.88", "0.9023",
             "<font color=\"#2E6E4E\"><b>MET</b></font>"],
            ["Voice path, F1 — clean transcripts", "> 0.90", "0.9401",
             "<font color=\"#2E6E4E\"><b>MET</b></font>"],
            ["Voice path, F1 — degraded transcripts (the realistic "
             "condition)", "> 0.90", "0.8709",
             "<font color=\"#A33A28\"><b>NOT MET</b></font>"],
            ["Glove accuracy, per window", "> 0.95", "0.8886",
             "<font color=\"#A33A28\"><b>NOT MET</b></font>"],
            ["System true-positive rate", "> 95%", "not measured",
             "<font color=\"#A33A28\"><b>NOT EVIDENCED</b></font>"],
            ["System false-positive rate", "< 3%", "not measured",
             "<font color=\"#A33A28\"><b>NOT EVIDENCED</b></font>"],
        ],
        widths=[46, 13, 19, 22],
        aligns=["LEFT", "CENTER", "CENTER", "CENTER"]))
    f.append(SP(12))
    f.append(P(
        "<b>The glove miss is not closable by tuning.</b> 0.8886 against 0.95 "
        "is 6.1 points, far outside the range a threshold or a gate could "
        "recover. The cross-validated 94.3 per cent fall detection answers a "
        "different question — per event rather than per window — and "
        "must not be quoted against a per-window accuracy target."))
    f.append(P(
        "<b>The system-level goals are not evidenced at all.</b> No individual "
        "model reaches 95 per cent recall; the strongest are the voice path at "
        "0.9675 on clean transcripts only and the glove's cross-validated 94.3 "
        "per cent per-event fall detection. The fused system's true-positive "
        "rate has never been measured end to end, because doing so requires "
        "hardware in the loop and a dispatched alert. The 3 per cent "
        "false-positive goal sits against the finding that 20.6 per cent of "
        "real weapon-free frames fire at the deployed floor on the shipped "
        "model."))
    f.append(NOTE(
        "Nothing was reframed to produce this table",
        "The only metric change against earlier reporting is giving the weapon "
        "detector in mAP@0.5 rather than at its operating point — and that "
        "is the metric the specification itself names. Both are recorded in "
        "section 9, and the difference between them is stated explicitly rather "
        "than left for a reader to miss."))
    return f


def s13():
    f = H1("13", "Hardware bring-up, 4 November 2026")
    f.append(P(
        "Every measurement in sections 9 to 12 is model-level: real inference "
        "over real held-out data, with no hardware involved. On 4 November 2026 "
        "the assembled system was run on real devices for the first time. What "
        "follows is what that session established and what it found broken, "
        "because a bring-up that reported only successes would be worth "
        "nothing.", "lead"))

    f.append(H2(f"13.1{GAP}What ran"))
    f.append(P(
        "Glove and glasses both paired. A journey was armed, the glasses "
        "streamed to the phone, and the weapon detector ran on live video for "
        "the first time outside a test harness. Detection boxes drew in the "
        "correct position over the moving picture, which validated the "
        "coordinate geometry that unit tests could establish only in principle "
        "— a box read through the wrong convention is not visibly broken, "
        "it is a confident, precisely drawn rectangle over the wrong part of "
        "the frame."))
    f.append(TBL(
        ["Quantity", "Measured", "Note"],
        [
            ["Warm inference", "99 ms",
             "LiteRT compiled to the phone's GPU"],
            ["Cold start", "1,981 ms",
             "First inference, while the runtime compiled"],
            ["Stream frame rate", "3.1 fps",
             "Delivered by the glasses, not a detector limit"],
            ["Inference rate", "~1.9 per second", "—"],
            ["Dropped frames", "9", "All during cold start"],
        ],
        widths=[24, 20, 56],
        aligns=["LEFT", "CENTER", "LEFT"]))
    f.append(SP(10))
    f.append(P(
        "These are the first latency figures the project has ever had. Earlier "
        "documentation carried an assumed frame rate in a code comment; it has "
        "been replaced with the measured one, attributed to the device it was "
        "measured on."))

    f.append(H2(f"13.2{GAP}Three defects the session found"))
    f.append(NUMBERED([
        "<b>A knife was reported as a pistol.</b> The inference plugin's "
        "Android layer hardcodes an empty label list, so class names never "
        "reach the detector and each detection arrived named "
        "<font name=\"Courier\">class 0</font> or <font name=\"Courier\">class "
        "1</font>. The index was correct; the name was synthetic. The mapping "
        "was then verified against ground truth rather than assumed — the "
        "shipped model was run over single-class images from the locked test "
        "split and agreed with the labels on 59 of 60 — which established "
        "that the model distinguishes knives from pistols in-domain and that "
        "the defect was purely in naming. A label file is now bundled and the "
        "index resolved against it.",
        "<b>The interface claimed to be watching a camera that was off.</b> "
        "During a journey the camera is opened by a trigger, so a loaded "
        "detector routinely receives nothing — and the status line read "
        "‘Watching — no weapon detected’, which is the "
        "application asserting it looked at the street and found it calm. This "
        "is the absent-is-not-zero invariant of section 6.3 violated in the "
        "user interface. It now distinguishes the two states.",
        "<b>Three failure states were indistinguishable.</b> A silently "
        "discarded exception meant that a detector throwing on every frame, a "
        "camera that never opened, and a detector running and finding nothing "
        "all looked identical on screen and in the logs. Rate-limited logging "
        "on both the success and failure paths was added, and it produced the "
        "diagnosis above within one session.",
    ]))

    f.append(H2(f"13.3{GAP}Why the knife still read as a pistol, and the fix"))
    f.append(P(
        "With the label defect fixed, a knife held in front of the camera still "
        "misclassified. Eleven frames were captured directly from the glasses "
        "to a workstation and scored: they arrive at <b>320×240 and about "
        "3.6 kB each</b>, and one weapon-free frame scored pistol at 0.351 "
        "against a bare wall."))
    f.append(P(
        "The cause is in the glasses firmware, not the model. The project's own "
        "stream-protocol measurements, taken on 3 October 2026, had already "
        "established the mechanism: at native resolution the detector scored "
        "91.2 per cent; at QVGA alone 89.2 per cent; at full resolution with "
        "heavy compression 90.4 per cent; and at <b>QVGA combined with heavy "
        "compression, 80.8 to 88.4 per cent</b>. Neither setting is the problem "
        "on its own, and together they are. At 320×240 a knife blade is a "
        "few pixels wide, and JPEG compression then quantises away precisely "
        "the high-frequency detail that distinguishes a blade."))
    f.append(P(
        "The firmware was configured at the worst corner of that grid: QVGA, "
        "quality 20, one frame buffer. Three configuration lines have been "
        "changed to VGA, quality 12 and two frame buffers — each change "
        "matching what the surrounding comments had argued for all along. The "
        "stuttering that originally caused the resolution to be reduced was "
        "measured with a single frame buffer, so frame size and buffer count "
        "had never been varied independently."))
    f.append(NOTE(
        "The status of this fix",
        "The change is written and saved. It has <b>not</b> been flashed, and "
        "the before-and-after measurement that would prove it — frames "
        "captured with a knife in view, scored against the 320×240 "
        "baseline — has not been taken. It is stated here as a diagnosed "
        "cause with an evidenced remedy, not as a resolved defect.",
        tone="caution"))

    f.append(H2(f"13.4{GAP}What the session established about the alarm"))
    f.append(P(
        "The alarm would not have fired. Of fourteen detections produced with a "
        "knife in view, only three reached the 0.55 confidence floor. The best "
        "fifteen-frame window held two qualifying hits, giving a weapon score "
        "of 0.08 against a 0.75 threshold; even at perfect persistence the "
        "ceiling on those confidences would have been 0.65."))
    f.append(P(
        "Lowering the confidence floor would have made a demonstration work. It "
        "was not lowered. The floor is what suppresses the 20.3 per cent "
        "false-positive rate of section 9.4, and trading that away to make a "
        "live demonstration succeed would be exactly the re-framing the "
        "standing rule of section 1.2 forbids."))
    return f


def s14():
    f = H1("14", "What this system has not been shown to do")
    f.append(P(
        "This section exists because a reader is entitled to know the boundary "
        "of the evidence without having to infer it from what is missing "
        "elsewhere.", "lead"))

    f.append(H2(f"14.1{GAP}The central limitation"))
    f.append(NOTE(
        "Model-level evidence, not system-level evidence",
        "The accuracy figures in this document are real, reproducible, and "
        "measured on data the models never trained on. What they establish is "
        "that each model performs as stated <b>on its own test distribution</b>. "
        "The system-level claim — that this assembly detects threats in "
        "the field — is not supported by anything here. No alert has ever "
        "been dispatched in a test, no false positive has been observed end to "
        "end, and the fused true-positive rate has never been measured.",
        tone="caution"))

    f.append(H2(f"14.2{GAP}By subsystem"))
    f.append(TBL(
        ["Area", "Not established"],
        [
            ["Voice", "The corpus is synthetic text-to-speech throughout. "
                      "Nobody in it is frightened. Real-world recall on a "
                      "distressed human voice is unproven. Specificity rests on "
                      "18 distinct held-out normal phrases."],
            ["Weapon", "Measured on public-dataset photographs, not on footage "
                       "from the SafeHer glasses. The 2026-11-04 session "
                       "established that in-domain accuracy does not transfer "
                       "to 320×240 glasses frames. 20.3 per cent of real "
                       "weapon-free frames fire at the deployed floor."],
            ["Motion", "208 recordings from one data-collection campaign. "
                       "Different people, floors and glove fits are untested. "
                       "The per-window specification target is missed by 6.1 "
                       "points."],
            ["Glove, end to end", "Firmware is hardware-validated on a real "
                                  "ESP32-C3. Physical motion through the full "
                                  "application path — notify, vote, "
                                  "foreground service, woken screen — has "
                                  "been exercised far less than the rest of the "
                                  "system, and no one has yet put a phone in a "
                                  "pocket and confirmed an alarm still gets "
                                  "out."],
            ["Facial expression", "Its accuracy figures are the training run's "
                                  "own and have never been independently "
                                  "re-measured; the test corpora are no longer "
                                  "on disk. They must not be quoted as tested. "
                                  "It is barred from the threat score."],
            ["Evidence, path two", "The server-side fusion path notifies "
                                   "contacts but starts no recorder. See "
                                   "section 7.3."],
            ["Operational", "Battery life, thermal behaviour and sustained "
                            "frame rate on the real devices are unmeasured "
                            "beyond the single session in section 13."],
            ["Hardware that does not exist", "The mobile interface shows a "
                                             "‘smart ring’ and a "
                                             "‘pendant’. No firmware "
                                             "exists for either. Only the glove "
                                             "and glasses are real."],
        ],
        widths=[20, 80]))
    f.append(SP(10))
    f.append(P(
        "Two further constraints affect reproducibility rather than capability. "
        "The weapon, voice and expression models cannot be retrained from a "
        "clean checkout — their datasets run to gigabytes and live outside "
        "the repository, so only the shipped artifacts and their measured "
        "results are committed. The glove's model <i>is</i> fully reproducible "
        "from the repository. And one source dataset carries a licence conflict "
        "— its README states CC BY-SA 4.0 while its licence file states CC "
        "BY 4.0 — which is treated as ShareAlike until the maintainers "
        "confirm."))
    return f


def s15():
    f = H1("15", "Reproducibility")
    f.append(P(
        "Every figure in sections 9 to 12 was produced by a committed script "
        "reading a committed artifact, with the artifact's SHA-256 verified "
        "before measurement. The hashes below identify exactly which bytes were "
        "measured.", "lead"))
    f.append(TBL(
        ["Artifact", "Size", "SHA-256 (first 32 hex characters)"],
        [
            ["Weapon detector, phone fp16 TFLite", "6,129,672 B",
             "afcfbe8c8664e2ecf34bd74ff32ac55c"],
            ["Weapon detector, server int8 ONNX", "3,355,730 B",
             "45811e6a65ab995363f9d97e59cd9f77"],
            ["Voice phrase classifier, JSON", "387,427 B",
             "18221931a2976a2c60d46078c4e3f0a5"],
            ["Glove motion classifier, XGBoost JSON", "3,278,020 B",
             "5f649215fb15143a4941d4c0b7daa5c9"],
        ],
        widths=[42, 16, 42],
        aligns=["LEFT", "CENTER", "LEFT"],
        font_rows={2: "mono"}))
    f.append(SP(12))
    f.append(KV([
        ("Measurement environment", "Python 3.12.5, onnxruntime 1.29.0, "
                                    "ai-edge-litert 2.3.0, numpy 2.3.5, "
                                    "Pillow 12.3.0, win32, CPU execution "
                                    "provider"),
        ("Hardware measurements", "Samsung SM-M166P, arm64-v8a, Android 15, "
                                  "LiteRT on GPU, 4 November 2026"),
        ("Test suites", "614 Python tests passing (7 skipped, all requiring a "
                        "gateway that is not running); 1,193 Dart tests "
                        "passing; static analysis clean on both library and "
                        "test code"),
        ("Figures", "Regenerated from the shipped artifacts and the locked test "
                    "splits by two committed scripts, each recording the "
                    "artifact hash it measured. No figure in this document is a "
                    "screenshot of a session"),
    ], label_w=24))
    f.append(SP(12))

    f.append(H2(f"15.1{GAP}Illustration, which is not measurement"))
    f.append(P(
        "The figure below shows what a detection looks like. It is not a "
        "metric, and twelve pictures cannot establish a rate. The sample was "
        "chosen mechanically — every <i>n</i>th image of the sorted test "
        "split listing, not hand-picked — and drawn at the 0.55 confidence "
        "floor the application actually applies rather than at a flattering low "
        "threshold. Eleven of the twelve produced a correct detection between "
        "0.60 and 0.93 confidence; one produced nothing at all, and that "
        "failure is kept in the sample deliberately. Its ground truth is a "
        "knife occupying about 3.4 per cent of the frame in the top-right "
        "corner, and the model did not reach the floor on it."))
    pair = _side_by_side(
        f"{FIGDIR}/annotated_detections/test_000162_knife_602.jpg",
        f"{FIGDIR}/annotated_detections/test_000000_e0dc90a20648d735.jpg",
        "_detection_pair.png")
    f.append(FIG(pair, "Figure 5",
                 "Two of the twelve, drawn at the deployed 0.55 floor. Left: a "
                 "knife detected at 0.84. Right: the one image in the sample "
                 "that produced nothing — its ground truth is the knife in "
                 "the top-right corner, and the model did not reach the floor "
                 "on it. Illustration, not measurement.",
                 max_h=72 * mm))

    f.append(H2(f"15.2{GAP}Closing note"))
    f.append(P(
        "The system described here works in the sense that each part does what "
        "it is documented to do, measured on data it has not seen. It does not "
        "yet work in the sense that matters most — nobody has been kept "
        "safe by it, and the end-to-end evidence for that claim does not exist. "
        "The gap between those two statements is stated throughout this "
        "document rather than closed by wording, and the work outstanding to "
        "close it properly is identified in section 14."))
    return f


def part_b():
    out = []
    for fn in (s7, s8, s9, s10, s11, s12, s13, s14, s15):
        out += fn()
    return out
