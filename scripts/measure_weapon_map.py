"""Re-measure mAP@0.5 for the shipped weapon artifacts against the SRS target.

The SRS fixes the benchmark for this model in section 6.1 as mAP@0.5 > 0.88.
Two separate artifacts ship from one set of weights -- the phone runs the fp16
TFLite and the server runs the int8 ONNX -- and the benchmark applies to both,
so both are measured here on the same 658-image test split.

The recorded figures (0.9056 phone, 0.9013 server) are not trusted as input:
they are read back only to report drift against a fresh measurement. One of
those numbers lives as a hard-coded constant inside the validation script that
produced the other, which is precisely the arrangement that lets a stale figure
outlive the artifact it described.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from ultralytics import YOLO

REPO = Path(r"C:\Users\AKSHAY_AG\Github\SafeHer")
ML = Path(r"D:\SafeHer-ML\weapon_detection")
DATA = ML / "datasets" / "merged" / "data.yaml"
OUT = Path(__file__).resolve().parent

SRS_TARGET_MAP50 = 0.88

ARTIFACTS = [
    # (key, path, what the project recorded previously)
    ("phone_fp16_tflite", REPO / "mobile/assets/models/weapon_yolov8n_fp16.tflite", 0.9056),
    ("server_int8_onnx", REPO / "ml_models/weapon_yolov8n_int8.onnx", 0.9013),
]


def measure(path: Path) -> dict:
    metrics = YOLO(str(path)).val(
        data=str(DATA),
        split="test",
        imgsz=640,
        batch=1,
        verbose=False,
        workers=0,
        device="cpu",
        plots=False,
        project=str(OUT / "val_runs"),
        name=path.stem,
        exist_ok=True,
    )
    box = metrics.box
    return {
        "map50": round(float(box.map50), 4),
        "map50_95": round(float(box.map), 4),
        "precision": round(float(box.mp), 4),
        "recall": round(float(box.mr), 4),
        "per_class_map50": {
            name: round(float(box.ap50[i]), 4)
            for i, name in enumerate(metrics.names.values())
            if i < len(box.ap50)
        },
    }


def main() -> None:
    results = {}
    for key, path, recorded in ARTIFACTS:
        if not path.exists():
            print(f"MISSING {path}", flush=True)
            continue
        print(f"\n{'=' * 70}\nmeasuring {key}: {path}\n{'=' * 70}", flush=True)
        try:
            got = measure(path)
        except Exception as exc:  # noqa: BLE001 - report, do not mask
            print(f"FAILED {key}: {type(exc).__name__}: {exc}", flush=True)
            results[key] = {"error": f"{type(exc).__name__}: {exc}"}
            continue
        got["recorded_map50"] = recorded
        got["drift_from_recorded"] = round(got["map50"] - recorded, 4)
        got["srs_target_map50"] = SRS_TARGET_MAP50
        got["meets_srs_target"] = got["map50"] > SRS_TARGET_MAP50
        results[key] = got
        print(json.dumps(got, indent=2), flush=True)

    (OUT / "weapon_map_remeasured.json").write_text(
        json.dumps(results, indent=2), encoding="utf-8"
    )
    print("\nwrote weapon_map_remeasured.json", flush=True)


if __name__ == "__main__":
    sys.exit(main())
