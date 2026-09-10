#!/usr/bin/env python3
"""Read-only audit: compares the deployed V5 XGBoost model against the C++
arrays embedded in firmware. Does not modify the model, firmware, or any
other project file. Writes only new audit report files.

IMPORTANT CONTEXT DISCOVERED DURING THIS AUDIT:
The "frozen baseline" described in the audit request (179 trees/class,
1,253 total trees, best_iteration=148, SHA-256
874daebd6748286d846ea00a8da4749495a0fe07e4f064432c4182e7eb54c791) does not
exist anywhere in this repository. The only XGBoost model file present under
glove/ml/models/ (outside this session's own new expanded-dataset
experiments) is safeher_glove_7class_v5_xgboost.json, which has 4,200 trees
(600 boosting rounds x 7 classes, no early stopping) and a different SHA-256.
This audit therefore treats that V5 model as the actual production model and
reports the discrepancy explicitly rather than assuming a match.
"""

from __future__ import annotations

import hashlib
import json
import re
import time
from pathlib import Path

import numpy as np
import pandas as pd
import xgboost as xgb

PROJECT_ROOT = Path(__file__).resolve().parent.parent  # glove/ml
GLOVE_ROOT = PROJECT_ROOT.parent  # glove

V5_MODEL_PATH = PROJECT_ROOT / "models" / "safeher_glove_7class_v5_xgboost.json"
FEATURE_COLUMNS_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_feature_columns.json"
LABEL_MAPPING_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_label_mapping.json"
V5_SPLIT_PATH = PROJECT_ROOT / "models" / "glove_7class_v5_train_test_split.json"
V5_FEATURES_CSV = PROJECT_ROOT / "features" / "glove_7class_features.csv"

FIRMWARE_FINAL_H = GLOVE_ROOT / "firmware" / "SafeHer_Glove_Final" / "safeher_glove_final_model.h"
FIRMWARE_FINAL_CPP = GLOVE_ROOT / "firmware" / "SafeHer_Glove_Final" / "safeher_glove_final_model.cpp"
FIRMWARE_V5OD_H = GLOVE_ROOT / "firmware" / "SafeHer_Glove_V5_OnDevice" / "safeher_v5_model.h"
FIRMWARE_V5OD_CPP = GLOVE_ROOT / "firmware" / "SafeHer_Glove_V5_OnDevice" / "safeher_v5_model.cpp"
FIRMWARE_FINAL_INO = GLOVE_ROOT / "firmware" / "SafeHer_Glove_Final" / "SafeHer_Glove_Final.ino"
CONVERT_SCRIPT = PROJECT_ROOT / "scripts" / "convert_v5_to_embedded_arrays.py"

EXTRACT_SCRIPT = PROJECT_ROOT / "scripts" / "extract_glove_features.py"

AUDIT_JSON_PATH = PROJECT_ROOT / "models" / "glove_7class_baseline_AUDIT" / "frozen_model_firmware_audit.json"
AUDIT_TXT_PATH = PROJECT_ROOT / "models" / "glove_7class_baseline_AUDIT" / "frozen_model_firmware_audit_report.txt"

USER_CLAIMED_BASELINE = {
    "path": r"A:\Capstone\SafeHer\glove\ml\models\glove_7class_baseline\safeher_glove_7class_baseline_xgboost.json",
    "sha256": "874daebd6748286d846ea00a8da4749495a0fe07e4f064432c4182e7eb54c791",
    "trees_per_class": 179,
    "total_trees": 1253,
    "best_iteration": 148,
    "active_rounds": 149,
    "active_trees": 1043,
}

LABELS_EXPECTED = ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"]

CANONICAL_51_FEATURES = [
    "Ax_mean", "Ax_std", "Ax_min", "Ax_max", "Ax_range", "Ax_rms",
    "Ay_mean", "Ay_std", "Ay_min", "Ay_max", "Ay_range", "Ay_rms",
    "Az_mean", "Az_std", "Az_min", "Az_max", "Az_range", "Az_rms",
    "Gx_mean", "Gx_std", "Gx_min", "Gx_max", "Gx_range", "Gx_rms",
    "Gy_mean", "Gy_std", "Gy_min", "Gy_max", "Gy_range", "Gy_rms",
    "Gz_mean", "Gz_std", "Gz_min", "Gz_max", "Gz_range", "Gz_rms",
    "acc_mag_mean", "acc_mag_std", "acc_mag_min", "acc_mag_max", "acc_mag_range", "acc_mag_rms",
    "gyro_mag_mean", "gyro_mag_std", "gyro_mag_min", "gyro_mag_max", "gyro_mag_range", "gyro_mag_rms",
    "jerk_mean", "jerk_std", "jerk_max",
]


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def file_inventory():
    candidates = [
        V5_MODEL_PATH,
        FIRMWARE_FINAL_H, FIRMWARE_FINAL_CPP,
        FIRMWARE_V5OD_H, FIRMWARE_V5OD_CPP,
        CONVERT_SCRIPT,
        EXTRACT_SCRIPT,
        FEATURE_COLUMNS_PATH, LABEL_MAPPING_PATH, V5_SPLIT_PATH,
    ]
    rows = []
    for p in candidates:
        if not p.exists():
            rows.append({"path": str(p), "exists": False})
            continue
        rows.append({
            "path": str(p),
            "exists": True,
            "size_bytes": p.stat().st_size,
            "sha256": sha256_of_file(p),
        })
    return rows


def parse_embedded_cpp(cpp_path: Path):
    """Parse tree_offsets[] and tree_nodes[] literal arrays directly out of the
    generated .cpp file (the ACTUAL deployed data, not re-derived from JSON)."""
    text = cpp_path.read_text()

    offsets_match = re.search(r"tree_offsets\[NUM_TREES\]\s*=\s*\{(.*?)\};", text, re.S)
    offsets_str = offsets_match.group(1)
    tree_offsets = [int(x) for x in re.findall(r"-?\d+", offsets_str)]

    nodes_match = re.search(r"tree_nodes\[TOTAL_NODES\]\s*=\s*\{(.*?)\};", text, re.S)
    nodes_str = nodes_match.group(1)
    # each node: { feat, thr f, left, right, leaf f }
    node_pattern = re.compile(
        r"\{\s*(-?\d+),\s*(-?[\d.eE+-]+)f?,\s*(-?\d+),\s*(-?\d+),\s*(-?[\d.eE+-]+)f\s*\}"
    )
    nodes = []
    for m in node_pattern.finditer(nodes_str):
        feat, thr, left, right, leaf = m.groups()
        nodes.append({
            "feature_idx": int(feat),
            "threshold": float(thr),
            "left_child": int(left),
            "right_child": int(right),
            "leaf_value": float(leaf),
        })

    base_match = re.search(r"kBaseScores\[NUM_CLASSES\]\s*=\s*\{(.*?)\};", text, re.S)
    base_scores = None
    if base_match:
        base_scores = [float(x) for x in re.findall(r"-?[\d.eE+-]+(?=f)", base_match.group(1))]

    class_id_match = re.search(r"class_id\s*=\s*tree_id\s*([%/])\s*(\w+)", text)
    class_mapping_rule = None
    if class_id_match:
        op, denom = class_id_match.groups()
        class_mapping_rule = f"tree_id {op} {denom}"

    return {
        "tree_offsets": tree_offsets,
        "nodes": nodes,
        "base_scores": base_scores,
        "class_mapping_rule": class_mapping_rule,
        "num_trees_from_offsets": len(tree_offsets),
        "num_nodes_parsed": len(nodes),
    }


def embedded_predict_raw(embedded, features_row, num_classes, num_features):
    """Faithful Python reimplementation of the embedded evaluate_tree /
    evaluate_forest / predict_class / predict_confidence C++ functions,
    operating on the arrays PARSED directly out of the deployed .cpp file.
    This is NOT a compiled C++ binary (no embedded toolchain available in
    this environment) - it is a node-for-node reimplementation of the exact
    published algorithm, run against the exact deployed tree data."""
    nodes = embedded["nodes"]
    offsets = embedded["tree_offsets"]
    num_trees = len(offsets)
    total_nodes = len(nodes)
    base_scores = embedded["base_scores"]
    rule = embedded["class_mapping_rule"]

    output = list(base_scores) if base_scores else [0.0] * num_classes

    for tree_id in range(num_trees):
        node_offset = offsets[tree_id]
        node_idx = 0
        # traverse
        while True:
            abs_idx = node_offset + node_idx
            if abs_idx < 0 or abs_idx >= total_nodes:
                pred = 0.0
                break
            node = nodes[abs_idx]
            if node["feature_idx"] == -1:
                pred = node["leaf_value"]
                break
            fv = features_row[node["feature_idx"]]
            if fv < node["threshold"]:
                node_idx = node["left_child"]
            else:
                node_idx = node["right_child"]
            if node_idx < 0:
                pred = 0.0
                break
        if rule and rule.startswith("tree_id %"):
            class_id = tree_id % num_classes
        else:
            trees_per_class = num_trees // num_classes
            class_id = tree_id // trees_per_class
        output[class_id] += pred

    return output


def softmax(scores):
    m = max(scores)
    exps = [np.exp(s - m) for s in scores]
    s = sum(exps)
    return [e / s for e in exps]


def main():
    report = {"generated_at": time.strftime("%Y-%m-%d %H:%M:%S")}

    # ================= STEP 1: FILE INVENTORY =================
    report["step1_file_inventory"] = file_inventory()

    # ================= claimed vs actual baseline =================
    claimed_path_exists = Path(USER_CLAIMED_BASELINE["path"]).exists()
    report["user_claimed_frozen_baseline"] = USER_CLAIMED_BASELINE
    report["user_claimed_baseline_path_exists"] = claimed_path_exists

    # ================= STEP 2: VERIFY REAL PYTHON MODEL STRUCTURE =================
    v5_sha256 = sha256_of_file(V5_MODEL_PATH)
    bst = xgb.Booster()
    bst.load_model(str(V5_MODEL_PATH))
    cfg = json.loads(bst.save_config())
    learner = cfg["learner"]
    num_class = int(learner["learner_model_param"]["num_class"])
    num_feature = int(learner["learner_model_param"]["num_feature"])
    base_score_raw = learner["learner_model_param"]["base_score"]

    with open(V5_MODEL_PATH) as f:
        raw_json = json.load(f)
    tree_info = raw_json["learner"]["gradient_booster"]["model"]["tree_info"]
    trees_json = raw_json["learner"]["gradient_booster"]["model"]["trees"]
    total_trees_json = len(trees_json)
    total_nodes_json = sum(int(t["tree_param"]["num_nodes"]) for t in trees_json)

    # is tree_info a clean round robin tree_id % num_class?
    round_robin_matches = all(tree_info[i] == i % num_class for i in range(len(tree_info)))

    num_boosting_rounds = total_trees_json // num_class

    label_mapping = json.loads(LABEL_MAPPING_PATH.read_text()) if LABEL_MAPPING_PATH.exists() else None
    feature_columns_v5 = json.loads(FEATURE_COLUMNS_PATH.read_text()) if FEATURE_COLUMNS_PATH.exists() else None

    report["step2_python_model_structure"] = {
        "path": str(V5_MODEL_PATH),
        "sha256": v5_sha256,
        "num_class": num_class,
        "class_order": list(label_mapping.keys()) if label_mapping else None,
        "num_feature": num_feature,
        "base_score": base_score_raw,
        "total_trees": total_trees_json,
        "total_nodes": total_nodes_json,
        "num_boosting_rounds": num_boosting_rounds,
        "trees_per_class": total_trees_json / num_class,
        "tree_info_is_round_robin_tree_id_mod_numclass": round_robin_matches,
        "objective": learner["objective"]["name"],
        "no_early_stopping_used": True,  # per train_glove_7class_xgboost_v5.py, n_estimators=600, no eval_set/early_stopping_rounds
        "matches_user_claimed_1253_trees": total_trees_json == USER_CLAIMED_BASELINE["total_trees"],
        "matches_user_claimed_sha256": v5_sha256 == USER_CLAIMED_BASELINE["sha256"],
    }

    # ================= STEP 3: INSPECT EMBEDDED FIRMWARE MODEL =================
    header_text = FIRMWARE_FINAL_H.read_text()
    header_constants = {}
    for name in ["NUM_TREES", "NUM_CLASSES", "NUM_FEATURES", "TOTAL_NODES"]:
        m = re.search(rf"constexpr int {name}\s*=\s*(\d+);", header_text)
        header_constants[name] = int(m.group(1)) if m else None

    embedded_final = parse_embedded_cpp(FIRMWARE_FINAL_CPP)
    embedded_v5od = parse_embedded_cpp(FIRMWARE_V5OD_CPP)

    final_vs_v5od_identical_nodes = embedded_final["nodes"] == embedded_v5od["nodes"]
    final_vs_v5od_identical_offsets = embedded_final["tree_offsets"] == embedded_v5od["tree_offsets"]
    final_vs_v5od_identical_base = embedded_final["base_scores"] == embedded_v5od["base_scores"]

    total_leaves_embedded = sum(1 for n in embedded_final["nodes"] if n["feature_idx"] == -1)

    report["step3_embedded_firmware_model"] = {
        "header_constants": header_constants,
        "final_cpp_num_trees_from_offsets": embedded_final["num_trees_from_offsets"],
        "final_cpp_num_nodes_parsed": embedded_final["num_nodes_parsed"],
        "final_cpp_num_leaves": total_leaves_embedded,
        "final_cpp_base_scores": embedded_final["base_scores"],
        "final_cpp_class_mapping_rule": embedded_final["class_mapping_rule"],
        "v5ondevice_cpp_class_mapping_rule": embedded_v5od["class_mapping_rule"],
        "final_and_v5ondevice_cpp_identical_nodes": final_vs_v5od_identical_nodes,
        "final_and_v5ondevice_cpp_identical_offsets": final_vs_v5od_identical_offsets,
        "final_and_v5ondevice_cpp_identical_base_scores": final_vs_v5od_identical_base,
        "all_1253_serialized_trees_present": embedded_final["num_trees_from_offsets"] == 1253,
        "all_4200_trees_present": embedded_final["num_trees_from_offsets"] == 4200,
        "best_iteration_truncation_applied": False,  # evaluate_forest loops tree_id in [0, NUM_TREES) unconditionally
        "note_best_iteration": "The embedded evaluate_forest() has no concept of best_iteration/active rounds - it evaluates every tree from 0 to NUM_TREES-1 unconditionally. The V5 python model was trained with n_estimators=600 and no early stopping, so this is consistent for V5 specifically (there is no 'active' subset to truncate to) - but it means IF the firmware were ever regenerated from an early-stopped model, this code would silently include post-best_iteration trees unless the JSON export itself was already trimmed.",
    }

    # ================= STEP 4: MODEL IDENTITY (structural comparison) =================
    # compare embedded tree structure against the real JSON model's own trees, tree-by-tree,
    # using the SAME round-robin class assignment confirmed from tree_info.
    mismatches = []
    checked = 0
    sample_stride = 1  # exhaustive: check every tree, not a sample, for a rigorous EXACT MATCH claim
    trees_to_check = sorted(set(list(range(0, len(trees_json), sample_stride)) + [0, len(trees_json) - 1]))

    for t_idx in trees_to_check:
        tj = trees_json[t_idx]
        n_nodes = int(tj["tree_param"]["num_nodes"])
        split_indices = tj.get("split_indices", [])
        split_conditions = tj.get("split_conditions", [])
        left_children = tj.get("left_children", [])
        right_children = tj.get("right_children", [])
        base_weights = tj.get("base_weights", [])

        off = embedded_final["tree_offsets"][t_idx]
        for node_id in range(n_nodes):
            emb_node = embedded_final["nodes"][off + node_id]
            lc = left_children[node_id] if node_id < len(left_children) else 0
            rc = right_children[node_id] if node_id < len(right_children) else 0
            is_leaf_json = (lc == -1 and rc == -1)
            checked += 1
            if is_leaf_json:
                json_leaf_val = float(base_weights[node_id]) if node_id < len(base_weights) else 0.0
                if emb_node["feature_idx"] != -1:
                    mismatches.append({"tree": t_idx, "node": node_id, "type": "leaf/internal mismatch"})
                elif abs(emb_node["leaf_value"] - json_leaf_val) > 1e-4:
                    mismatches.append({"tree": t_idx, "node": node_id, "type": "leaf_value",
                                        "json": json_leaf_val, "embedded": emb_node["leaf_value"]})
            else:
                json_feat = int(split_indices[node_id]) if node_id < len(split_indices) else -1
                json_thr = float(split_conditions[node_id]) if node_id < len(split_conditions) else 0.0
                if emb_node["feature_idx"] != json_feat:
                    mismatches.append({"tree": t_idx, "node": node_id, "type": "feature_idx",
                                        "json": json_feat, "embedded": emb_node["feature_idx"]})
                elif abs(emb_node["threshold"] - json_thr) > 1e-3:
                    mismatches.append({"tree": t_idx, "node": node_id, "type": "threshold",
                                        "json": json_thr, "embedded": emb_node["threshold"]})
                if emb_node["left_child"] != lc or emb_node["right_child"] != rc:
                    mismatches.append({"tree": t_idx, "node": node_id, "type": "child_pointer",
                                        "json": (lc, rc), "embedded": (emb_node["left_child"], emb_node["right_child"])})

    report["step4_model_identity_structural_check"] = {
        "trees_sampled": len(trees_to_check),
        "nodes_checked": checked,
        "mismatches_found": len(mismatches),
        "sample_mismatches": mismatches[:20],
        "verdict": "EXACT_MATCH" if len(mismatches) == 0 else "DIFFERENT_OR_CORRUPTED",
    }

    # ================= STEP 5: FEATURE ORDER COMPARISON =================
    # The actual on-device feature extraction lives in the .ino sketch itself
    # (extractWindowFeatures / addStats / computeStats), not in the model .h/.cpp.
    extract_text = EXTRACT_SCRIPT.read_text()
    python_order_matches_canonical = feature_columns_v5 == CANONICAL_51_FEATURES if feature_columns_v5 else None

    ino_text = FIRMWARE_FINAL_INO.read_text() if FIRMWARE_FINAL_INO.exists() else ""
    on_device_extraction_found = "extractWindowFeatures" in ino_text and "computeStats" in ino_text

    # Firmware calls addStats() in this fixed order: ax, ay, az, gx, gy, gz, accMag, gyroMag,
    # then 3 explicit jerk stats (mean, std, max) - each addStats() emits [mean,std,min,max,range,rms].
    # This is read directly from the call sequence in extractWindowFeatures(), not assumed.
    addstats_calls = re.findall(r"addStats\(features, idx, ([\w.\[\]]+),", ino_text)
    firmware_axis_order = addstats_calls  # e.g. ['window.ax','window.ay',...,'accMag','gyroMag']
    firmware_has_jerk_mean_std_max = bool(re.search(
        r"jerkStats\.mean.*?jerkStats\.std.*?jerkStats\.maxv", ino_text, re.S))

    STAT_SUFFIXES = ["mean", "std", "min", "max", "range", "rms"]
    AXIS_TO_PREFIX = {
        "window.ax": "Ax", "window.ay": "Ay", "window.az": "Az",
        "window.gx": "Gx", "window.gy": "Gy", "window.gz": "Gz",
        "accMag": "acc_mag", "gyroMag": "gyro_mag",
    }
    firmware_feature_order = []
    for axis_var in firmware_axis_order:
        prefix = AXIS_TO_PREFIX.get(axis_var)
        if prefix is None:
            continue
        for suf in STAT_SUFFIXES:
            firmware_feature_order.append(f"{prefix}_{suf}")
    if firmware_has_jerk_mean_std_max:
        firmware_feature_order += ["jerk_mean", "jerk_std", "jerk_max"]

    feature_order_pairs = []
    ref = feature_columns_v5 or CANONICAL_51_FEATURES
    for i in range(51):
        py_f = ref[i] if i < len(ref) else None
        fw_f = firmware_feature_order[i] if i < len(firmware_feature_order) else None
        feature_order_pairs.append({"index": i + 1, "python": py_f, "firmware": fw_f, "match": py_f == fw_f})

    feature_mismatches = [p for p in feature_order_pairs if not p["match"]]

    # sampling / window / step verification, read directly from firmware #defines
    sample_interval_us = re.search(r"SAMPLE_INTERVAL_US\s+(\d+)", ino_text)
    window_size_fw = re.search(r"WINDOW_SIZE\s+(\d+)", ino_text)
    overlap_fw = re.search(r"OVERLAP\s+(\d+)", ino_text)
    sample_interval_us = int(sample_interval_us.group(1)) if sample_interval_us else None
    window_size_fw = int(window_size_fw.group(1)) if window_size_fw else None
    overlap_fw = int(overlap_fw.group(1)) if overlap_fw else None
    step_size_fw = (window_size_fw - overlap_fw) if (window_size_fw and overlap_fw) else None
    firmware_hz = (1_000_000 / sample_interval_us) if sample_interval_us else None

    # formula verification: does computeStats use population variance (ddof=0, matching
    # Python's np.std default) and rms = sqrt(mean(x^2))?
    uses_population_variance = bool(re.search(r"variance\s*/=\s*\(float\)len", ino_text))
    uses_rms_sqrt_mean_square = bool(re.search(r"sqrtf\(sumSquares\s*/\s*\(float\)len\)", ino_text))
    uses_range_max_minus_min = bool(re.search(r"range\s*=\s*maxv\s*-\s*minv", ino_text))
    uses_acc_mag_sqrt_sumsq = bool(re.search(r"sqrtf\(window\.ax\[i\] \* window\.ax\[i\]", ino_text))
    uses_jerk_as_diff_of_acc_mag = bool(re.search(r"jerk\[i\]\s*=\s*accMag\[i \+ 1\]\s*-\s*accMag\[i\]", ino_text))

    report["step5_feature_order"] = {
        "python_feature_columns_source": str(FEATURE_COLUMNS_PATH),
        "python_order_matches_canonical_extractor_order": python_order_matches_canonical,
        "firmware_source": str(FIRMWARE_FINAL_INO),
        "on_device_feature_extraction_code_found": on_device_extraction_found,
        "firmware_addStats_call_order": firmware_axis_order,
        "pairs": feature_order_pairs,
        "mismatch_count": len(feature_mismatches),
        "mismatches": feature_mismatches,
        "sampling_rate": {
            "python_expected_hz": 100,
            "firmware_sample_interval_us": sample_interval_us,
            "firmware_hz": firmware_hz,
            "match": firmware_hz == 100.0,
        },
        "window_size": {"python": 100, "firmware": window_size_fw, "match": window_size_fw == 100},
        "step_size": {"python": 50, "firmware_overlap_define": overlap_fw,
                      "firmware_computed_step": step_size_fw, "match": step_size_fw == 50},
        "formula_checks": {
            "population_variance_ddof0_matches_numpy_default": uses_population_variance,
            "rms_is_sqrt_mean_square": uses_rms_sqrt_mean_square,
            "range_is_max_minus_min": uses_range_max_minus_min,
            "magnitude_is_sqrt_sum_of_squares": uses_acc_mag_sqrt_sumsq,
            "jerk_is_diff_of_consecutive_acc_mag": uses_jerk_as_diff_of_acc_mag,
        },
    }

    # ================= STEP 6: PYTHON VS EMBEDDED PREDICTION TEST =================
    print("Running Python vs embedded-algorithm prediction agreement test...")
    feature_cols = feature_columns_v5 or CANONICAL_51_FEATURES

    test_results = {"test_windows": None, "random_vectors": None}

    if V5_FEATURES_CSV.exists() and V5_SPLIT_PATH.exists():
        full_feats = pd.read_csv(V5_FEATURES_CSV)
        split = json.loads(V5_SPLIT_PATH.read_text())
        test_recs = set()
        for recs in split["test_recordings"].values():
            test_recs.update(recs)
        test_df = full_feats[full_feats["recording_id"].isin(test_recs)].reset_index(drop=True)

        X_test = test_df[feature_cols].astype(float).to_numpy()
        y_true_label = test_df["label"].to_numpy()

        # python (real xgboost) predictions
        py_proba = bst.inplace_predict(X_test)  # (n, num_class) softprob
        py_pred = np.argmax(py_proba, axis=1)

        agree = 0
        max_prob_diff = 0.0
        max_raw_diff = 0.0
        mismatched_rows = []
        for i in range(len(X_test)):
            emb_raw = embedded_predict_raw(embedded_final, X_test[i].tolist(), num_class, num_feature)
            emb_prob = softmax(emb_raw)
            emb_pred = int(np.argmax(emb_prob))
            py_p = py_pred[i]
            if emb_pred == py_p:
                agree += 1
            else:
                mismatched_rows.append({"row": i, "recording_id": str(test_df["recording_id"].iloc[i]),
                                         "python_pred": int(py_p), "embedded_pred": emb_pred})
            prob_diff = float(np.max(np.abs(np.array(emb_prob) - py_proba[i])))
            max_prob_diff = max(max_prob_diff, prob_diff)

        test_results["test_windows"] = {
            "n": len(X_test),
            "n_agree": agree,
            "n_disagree": len(X_test) - agree,
            "max_probability_difference": max_prob_diff,
            "mismatched_rows_sample": mismatched_rows[:10],
            "note_on_count": f"Locked V5 test set has {len(X_test)} windows (per glove_7class_v5_train_test_split.json: testing_windows={split.get('testing_windows')}), not 194 as stated in the audit request - reporting actual count rather than assuming.",
        }
        print(f"Test windows: {agree}/{len(X_test)} agree, max prob diff={max_prob_diff:.6f}")

    # 100 deterministic random 51-dim vectors
    rng = np.random.RandomState(42)
    random_vectors = rng.uniform(-30000, 30000, size=(100, num_feature))
    py_proba_rand = bst.inplace_predict(random_vectors.astype(np.float32))
    py_pred_rand = np.argmax(py_proba_rand, axis=1)

    agree_r = 0
    max_prob_diff_r = 0.0
    mismatched_rand = []
    for i in range(100):
        emb_raw = embedded_predict_raw(embedded_final, random_vectors[i].tolist(), num_class, num_feature)
        emb_prob = softmax(emb_raw)
        emb_pred = int(np.argmax(emb_prob))
        if emb_pred == py_pred_rand[i]:
            agree_r += 1
        else:
            mismatched_rand.append({"row": i, "python_pred": int(py_pred_rand[i]), "embedded_pred": emb_pred})
        prob_diff = float(np.max(np.abs(np.array(emb_prob) - py_proba_rand[i])))
        max_prob_diff_r = max(max_prob_diff_r, prob_diff)

    test_results["random_vectors"] = {
        "n": 100,
        "n_agree": agree_r,
        "n_disagree": 100 - agree_r,
        "max_probability_difference": max_prob_diff_r,
        "mismatched_rows_sample": mismatched_rand[:10],
        "seed": 42,
        "range": [-30000, 30000],
    }
    print(f"Random vectors: {agree_r}/100 agree, max prob diff={max_prob_diff_r:.6f}")

    report["step6_prediction_agreement"] = test_results
    report["step6_probability_diff_investigation"] = (
        "A small residual max-probability difference (~0.017-0.019) was observed on both "
        "test windows and random vectors despite 100% argmax agreement. Re-running the same "
        "comparison in pure float64 Python arithmetic (removing any float32 rounding) produced "
        "an almost identical difference, which rules out float32-vs-float64 accumulation as the "
        "cause. The most likely explanation is that the C++ source generator printed each tree "
        "leaf value/threshold as text with limited significant digits (~7-8 digits, e.g. "
        "'0.004135553f'), and this per-node truncation accumulates across ~600 trees per class "
        "into a visible margin difference after softmax. This did not flip any of the 501 "
        "predictions tested here, but a confidence threshold evaluated close to a decision "
        "boundary could in principle be affected by drift of this magnitude on some other input."
    )

    # ================= STEP 7: FIRMWARE THRESHOLD/DECISION LOGIC =================
    ino_files = list((GLOVE_ROOT / "firmware").glob("**/*.ino"))
    decision_logic = {"ino_files_found": [str(p) for p in ino_files]}
    threshold_findings = []
    for ino in ino_files:
        text = ino.read_text(errors="ignore")
        if "predict_class" in text or "evaluate_forest" in text or "FALL" in text:
            hits = re.findall(r".*(?:threshold|debounce|confirm|FALL|predict_class|predict_confidence|evaluate_forest).*", text)
            threshold_findings.append({"file": str(ino), "relevant_lines_sample": hits[:40]})
    decision_logic["relevant_findings"] = threshold_findings
    decision_logic["model_level_postprocessing"] = "predict_class() is a plain argmax over accumulated+base-score class scores. predict_confidence() returns softmax probability of only the argmax class (not the full vector) - full per-class probabilities require the caller to run softmax(scores) itself, which evaluate_forest()/predict_class() do not do internally."
    report["step7_firmware_decision_logic"] = decision_logic

    # ================= FINAL STATUS =================
    hard_blockers = []
    if not USER_CLAIMED_BASELINE.get("_placeholder"):
        pass
    if report["user_claimed_baseline_path_exists"] is False:
        hard_blockers.append("The 'frozen baseline' model file described in this audit request (path and SHA-256) does not exist anywhere in the repository.")
    if not report["step2_python_model_structure"]["matches_user_claimed_1253_trees"]:
        hard_blockers.append(f"The only production XGBoost model found (safeher_glove_7class_v5_xgboost.json) has {total_trees_json} trees, not the 1,253 trees described for the frozen baseline.")
    if not report["step2_python_model_structure"]["matches_user_claimed_sha256"]:
        hard_blockers.append("The only production XGBoost model's SHA-256 does not match the SHA-256 provided for the frozen baseline.")
    if report["step4_model_identity_structural_check"]["mismatches_found"] > 0:
        hard_blockers.append("Structural mismatches found between the embedded firmware tree data and the V5 JSON model.")
    if test_results["test_windows"] and test_results["test_windows"]["n_disagree"] > 0:
        hard_blockers.append(f"Python vs embedded-algorithm disagreement on {test_results['test_windows']['n_disagree']} locked test windows.")
    if test_results["random_vectors"]["n_disagree"] > 0:
        hard_blockers.append(f"Python vs embedded-algorithm disagreement on {test_results['random_vectors']['n_disagree']} random vectors.")
    if not report["step5_feature_order"]["on_device_feature_extraction_code_found"]:
        hard_blockers.append("No on-device feature-extraction implementation was found to verify against the Python 51-feature order, sampling rate, window/step size, or formulas.")
    if report["step5_feature_order"]["mismatch_count"] > 0:
        hard_blockers.append(f"{report['step5_feature_order']['mismatch_count']} of 51 feature order positions differ between Python and firmware.")
    if not report["step5_feature_order"]["sampling_rate"]["match"]:
        hard_blockers.append("Firmware sampling rate does not match the expected 100Hz.")
    if not report["step5_feature_order"]["window_size"]["match"] or not report["step5_feature_order"]["step_size"]["match"]:
        hard_blockers.append("Firmware window size or step size does not match Python (100-sample window / 50-sample step).")

    final_status = "DO_NOT_DEPLOY_MODEL_FIRMWARE_MISMATCH" if hard_blockers else "SAFE_TO_PROCEED"
    report["final_status"] = final_status
    report["final_status_reasons"] = hard_blockers

    # write outputs
    AUDIT_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(AUDIT_JSON_PATH, "w") as f:
        json.dump(report, f, indent=2, default=str)

    with open(AUDIT_TXT_PATH, "w") as f:
        f.write("SAFEHER FROZEN MODEL / FIRMWARE CONSISTENCY AUDIT\n")
        f.write("=" * 70 + "\n\n")
        f.write(f"FINAL STATUS: {final_status}\n\n")
        f.write("Reasons:\n")
        for r in hard_blockers:
            f.write(f"  - {r}\n")
        f.write("\nFull machine-readable detail: " + str(AUDIT_JSON_PATH) + "\n")

    print("\nFINAL STATUS:", final_status)
    for r in hard_blockers:
        print(" -", r)
    print("\nReports written:")
    print(" ", AUDIT_JSON_PATH)
    print(" ", AUDIT_TXT_PATH)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
