"""Produce a visual record of the weapon-detector evaluation.

Two different kinds of output, and the distinction matters because one is
evidence and the other is illustration:

  * The validation plots -- precision-recall curve, F1-versus-confidence curve,
    confusion matrix -- ARE the measurement, drawn. They are computed over all
    658 test images and 783 instances by the same ultralytics val pass that
    produced the mAP figure, so nothing in them is a selected example.

  * The annotated prediction images are ILLUSTRATION. They show what a detection
    looks like on images the model never trained on, which is worth seeing, but
    a dozen pictures are not a metric and must never be captioned as though they
    were. They are drawn at the confidence floor the app actually applies (0.55)
    rather than at a flattering low threshold, and the sample is taken on a
    fixed stride through the directory listing rather than hand-picked, so it
    includes whatever the model gets wrong.

Both are generated from the shipped artifact, whose hash is recorded in the
manifest alongside them.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from ultralytics import YOLO

REPO = Path(r"C:\Users\AKSHAY_AG\Github\SafeHer")
ML = Path(r"D:\SafeHer-ML\weapon_detection")
DATA = ML / "datasets" / "merged" / "data.yaml"
TEST_IMAGES = ML / "datasets" / "merged" / "images" / "test"

SHIPPED = REPO / "mobile/assets/models/weapon_yolov8n_fp16.tflite"
OUT = REPO / "docs" / "assets" / "evaluation"
SCRATCH = Path(__file__).resolve().parent

CONF_FLOOR = 0.55  # WeaponScorer.confidenceFloor
SAMPLE_COUNT = 12


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "artifact": str(SHIPPED.relative_to(REPO)).replace("\\", "/"),
        "artifact_sha256": sha256(SHIPPED),
        "test_split": {
            "path": str(TEST_IMAGES),
            "images": len(list(TEST_IMAGES.glob("*.jpg"))),
            "note": "Locked test split. Held out from training by directory, "
                    "70/20/10 by image, seed 20260830.",
        },
        "confidence_floor": CONF_FLOOR,
        "figures": {},
    }

    # ---- 1. The measurement, drawn. Full test split, plots enabled. ----
    print("=" * 70, flush=True)
    print("validation pass with plots over all 658 test images", flush=True)
    print("=" * 70, flush=True)
    run_dir = SCRATCH / "evidence_val"
    if run_dir.exists():
        shutil.rmtree(run_dir, ignore_errors=True)
    metrics = YOLO(str(SHIPPED)).val(
        data=str(DATA), split="test", imgsz=640, batch=1, verbose=False,
        workers=0, device="cpu", plots=True,
        project=str(run_dir), name="shipped_phone_fp16", exist_ok=True,
    )
    box = metrics.box
    manifest["measured"] = {
        "map50": round(float(box.map50), 4),
        "map50_95": round(float(box.map), 4),
        "per_class_map50": {
            name: round(float(box.ap50[i]), 4)
            for i, name in enumerate(metrics.names.values())
            if i < len(box.ap50)
        },
        "instances": 783,
        "images": 658,
    }
    print(json.dumps(manifest["measured"], indent=2), flush=True)

    produced = run_dir / "shipped_phone_fp16"
    wanted = {
        "BoxPR_curve.png": "precision_recall_curve.png",
        "BoxF1_curve.png": "f1_vs_confidence_curve.png",
        "BoxP_curve.png": "precision_vs_confidence_curve.png",
        "BoxR_curve.png": "recall_vs_confidence_curve.png",
        "confusion_matrix.png": "confusion_matrix.png",
        "confusion_matrix_normalized.png": "confusion_matrix_normalised.png",
    }
    for source, target in wanted.items():
        src = produced / source
        if src.exists():
            shutil.copy2(src, OUT / target)
            manifest["figures"][target] = "measurement over the full test split"
            print(f"  kept {target}", flush=True)
        else:
            print(f"  MISSING {source}", flush=True)

    # The label/prediction grids ultralytics draws for its own val batches.
    for src in sorted(produced.glob("val_batch*_pred.jpg"))[:3]:
        target = f"val_{src.stem}.jpg"
        shutil.copy2(src, OUT / target)
        manifest["figures"][target] = "val batch predictions, drawn by ultralytics"
        print(f"  kept {target}", flush=True)
    for src in sorted(produced.glob("val_batch*_labels.jpg"))[:3]:
        target = f"val_{src.stem}.jpg"
        shutil.copy2(src, OUT / target)
        manifest["figures"][target] = "val batch ground-truth labels, for comparison"
        print(f"  kept {target}", flush=True)

    # ---- 2. Illustration. Annotated detections at the deployed floor. ----
    print("\n" + "=" * 70, flush=True)
    print(f"annotated detections at the deployed floor conf={CONF_FLOOR}", flush=True)
    print("=" * 70, flush=True)
    listing = sorted(TEST_IMAGES.glob("*.jpg"))
    stride = max(len(listing) // SAMPLE_COUNT, 1)
    sample = listing[::stride][:SAMPLE_COUNT]

    predict_dir = SCRATCH / "evidence_pred"
    if predict_dir.exists():
        shutil.rmtree(predict_dir, ignore_errors=True)
    model = YOLO(str(SHIPPED))
    detections = []
    for image in sample:
        results = model.predict(
            source=str(image), imgsz=640, conf=CONF_FLOOR, device="cpu",
            save=True, verbose=False,
            project=str(predict_dir), name="annotated", exist_ok=True,
        )
        result = results[0]
        found = [
            {
                "class": result.names[int(c)],
                "confidence": round(float(p), 4),
            }
            for c, p in zip(result.boxes.cls.tolist(), result.boxes.conf.tolist())
        ]
        detections.append({"image": image.name, "detections": found})
        print(f"  {image.name}: {found if found else 'nothing above the floor'}",
              flush=True)

    annotated_out = OUT / "annotated_detections"
    annotated_out.mkdir(exist_ok=True)
    for src in sorted((predict_dir / "annotated").glob("*.jpg")):
        shutil.copy2(src, annotated_out / src.name)

    manifest["annotated_detections"] = {
        "what_this_is": "ILLUSTRATION, not a metric. A fixed-stride sample of the "
                        "held-out test split, drawn at the confidence floor the "
                        "app applies. Includes whatever the model misses.",
        "sampling": f"every {stride}th image of the sorted listing, first "
                    f"{SAMPLE_COUNT}",
        "confidence_floor": CONF_FLOOR,
        "results": detections,
    }

    (OUT / "MANIFEST.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    print(f"\nwrote {OUT / 'MANIFEST.json'}", flush=True)
    print(f"figures in {OUT}", flush=True)


if __name__ == "__main__":
    main()
