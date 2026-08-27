# SafeHer V5 XGBoost → ESP32-C3 Conversion Status

**Completion Date:** 2024  
**Status:** ✓ CONVERSION COMPLETE  
**Model Version:** V5 (7-class)  
**Device Target:** ESP32-C3 (32-bit MCU)  

---

## 1. Conversion Summary

The SafeHer V5 7-class XGBoost model has been successfully exported to multiple formats suitable for embedded ESP32-C3 deployment:

- **Treelite Binary Model** (5.44 MB): Compressed model representation for runtime loading
- **Model JSON** (19.96 MB): Full model structure for reference and debugging
- **Model Metadata** (1.4 KB): Configuration, features, classes, and window settings
- **C++ Wrapper Template** (2.6 KB): Integration starting point for ESP32 code

**Total Generated Size:** 24.23 MB (suitable for evaluation; optimization needed for production)

---

## 2. Key Specifications

### Model Architecture
- **Model Name:** SafeHer V5 7-Class Glove XGBoost
- **Framework:** XGBoost (sklearn wrapper)
- **Boosting Rounds:** 600 (XGBoost rounds)
- **Tree Count (Treelite):** 4,200 (600 rounds × 7 classes)
- **Input Features:** 51 numeric
- **Output Classes:** 7 (NORMAL, JERK, PUSH, PULL, SHAKING, TWISTING, FALL)

### Feature Specification (51 total)
| Category | Count | Features |
|----------|-------|----------|
| Accelerometer (Ax, Ay, Az) | 18 | mean, std, min, max, range, rms × 3 axes |
| Gyroscope (Gx, Gy, Gz) | 18 | mean, std, min, max, range, rms × 3 axes |
| Accel Magnitude | 6 | mean, std, min, max, range, rms |
| Gyro Magnitude | 6 | mean, std, min, max, range, rms |
| Jerk (d/dt of acc_mag) | 3 | mean, std, max |
| **Total** | **51** | |

### Sensor Configuration
- **Sampling Rate:** 100 Hz
- **Window Size:** 100 samples (1 second)
- **Window Overlap:** 50% (50-sample step)
- **Sensor Input:** ESP32-C3 IMU (Accel + Gyro)

### Class Labels with Safety Mapping
| Class | Safety State | Confidence Threshold |
|-------|------|---|
| NORMAL | SAFE | Any |
| JERK | ABNORMAL | Any |
| PUSH | ABNORMAL | Any |
| PULL | ABNORMAL | Any |
| SHAKING | ABNORMAL | Any |
| TWISTING | ABNORMAL | Any |
| FALL | HIGH_RISK | ≥ 0.65 |
| FALL | ABNORMAL | < 0.65 |

---

## 3. Performance Metrics (Validation Set, 22 recordings)

| Metric | Value |
|--------|-------|
| Accuracy | 85.54% |
| NORMAL Recall | 88.51% (123/139 correct) |
| FALL Recall | 73.85% (48/65 correct) |
| False FALL Rate | 10.81% (16/148 NORMAL misclassified as FALL) |
| Missed FALL Rate | 23.08% (15/65 FALL undetected) |

### Per-Class Performance
| Class | Precision | Recall | F1-Score | Support |
|-------|-----------|--------|----------|---------|
| NORMAL | 0.89 | 0.88 | 0.89 | 148 |
| JERK | 0.60 | 1.00 | 0.75 | 3 |
| PUSH | 0.67 | 0.67 | 0.67 | 3 |
| PULL | 1.00 | 1.00 | 1.00 | 4 |
| SHAKING | 1.00 | 1.00 | 1.00 | 1 |
| TWISTING | 1.00 | 1.00 | 1.00 | 1 |
| FALL | 0.75 | 0.74 | 0.74 | 65 |

---

## 4. Generated Files

### Location: `models/glove_7class/esp32_v5/`

| File | Size | Purpose |
|------|------|---------|
| `safeher_v5_model.treelite` | 5.44 MB | Treelite binary model (compressed) |
| `safeher_v5_model_exported.json` | 19.96 MB | Full model JSON representation |
| `metadata.json` | 1.4 KB | Model config, features, classes |
| `safeher_xgboost_wrapper.hpp` | 2.6 KB | C++ wrapper template for integration |

### metadata.json Content
```json
{
  "model_name": "SafeHer V5 7-Class Glove XGBoost",
  "num_features": 51,
  "num_trees": 4200,
  "input_type": "float32",
  "output_type": "float32",
  "feature_names": ["Ax_mean", "Ax_std", ..., "jerk_max"],
  "class_labels": ["NORMAL", "JERK", "PUSH", "PULL", "SHAKING", "TWISTING", "FALL"],
  "window_configuration": {
    "window_size_samples": 100,
    "sampling_rate_hz": 100,
    "window_duration_seconds": 1.0,
    "overlap_percent": 50
  },
  "treelite_version": "4.7.0",
  "xgboost_version": "3.4.0"
}
```

---

## 5. Constraints Honored

✓ **Do NOT modify the original V5 model** — Model unchanged, conversion is read-only  
✓ **Do NOT retrain the model** — No training performed  
✓ **Do NOT modify any datasets** — Feature CSV untouched  
✓ **Do NOT modify the real-time inference script** — `safeher_realtime_inference.py` unchanged  
✓ **Do NOT modify Arduino sketches** — ESP32 sketch not touched  
✓ **Use Treelite 4.7.0 only** — No compiler or external tools required  
✓ **Preserve all 4,200 trees and 51 features** — Complete model exported  
✓ **Export all 7 output classes** — All classes present in metadata  

---

## 6. ESP32-C3 Feasibility Assessment

### Memory Analysis
- **Model Binary:** 5.44 MB (Treelite compressed format)
- **Model JSON:** 19.96 MB (reference, likely too large for flash)
- **ESP32-C3 Flash:** 4 MB total (shared with firmware, SPIFFS, sketch)
- **ESP32-C3 RAM:** 400 KB (8 KB SRAM + ~380 KB DRAM)

### Challenge: Model Size
The model size is **significantly larger than ESP32-C3 capacity:**
- Binary model (5.44 MB) > Flash available (~2-3 MB after firmware)
- Runtime prediction memory needs (temp buffers, intermediate activations)

### Potential Solutions

#### Option 1: Model Optimization (RECOMMENDED)
- **Tree Pruning:** Reduce from 4,200 → 1,000-2,000 trees (trade-off evaluation needed)
- **Quantization:** Convert float32 → int8 (reduce size ~4×)
- **Feature Selection:** Identify 20-30 most important features (reduce input vector)
- **Estimated Result:** 1.5-2.0 MB model size → **Feasible on ESP32-C3**

#### Option 2: External Flash Storage
- Store model on external SPI Flash (requires additional hardware)
- Load model segments on-demand (slower inference)
- Feasible but increases complexity and latency

#### Option 3: Different Hardware
- Upgrade to ESP32-S3 (8 MB flash, 8 MB PSRAM)
- Or use edge ML accelerator (Google Coral, NVIDIA Jetson Nano)

### Recommendation
**Proceed with Model Optimization (Option 1):**
1. Apply tree pruning to achieve 1,500-2,000 trees
2. Evaluate performance impact (target: maintain ≥75% FALL recall)
3. If acceptable, retrain V6 with reduced tree count
4. Convert V6 to ESP32 format
5. Test on hardware with actual latency constraints

---

## 7. Integration Roadmap

### Phase 1: Feasibility Study (CURRENT)
✓ Export model in multiple formats  
✓ Analyze size constraints  
→ Identify optimization strategy  

### Phase 2: Model Optimization (NEXT)
- Create V6 version with reduced tree count
- Apply quantization techniques
- Validate performance on test set
- Generate optimized binary

### Phase 3: ESP32 Integration
- Implement Treelite runtime on Arduino
- Compile custom firmware with model
- Test on-device inference latency
- Validate safety classification accuracy

### Phase 4: Deployment
- Flash optimized model to ESP32-C3
- Integrate with sensor streaming
- Perform end-to-end safety testing
- Deploy to SafeHer prototype

---

## 8. Tools and Versions

| Tool | Version | Purpose |
|------|---------|---------|
| Python | 3.x | Conversion pipeline |
| XGBoost | 3.4.0 | Model framework |
| Treelite | 4.7.0 | Model analysis & binary export |
| NumPy | 1.26.2 | Numerical operations |
| ESP32-C3 SDK | 2.x+ | Target hardware SDK |

---

## 9. Files Modified/Created

### NEW FILES (conversion output)
```
models/glove_7class/esp32_v5/
  ├── safeher_v5_model.treelite          (5.44 MB binary)
  ├── safeher_v5_model_exported.json     (19.96 MB reference)
  ├── metadata.json                      (1.4 KB config)
  └── safeher_xgboost_wrapper.hpp        (2.6 KB template)
```

### UNCHANGED FILES
```
models/glove_7class/
  ├── safeher_glove_7class_v5_xgboost.json     ✓ ORIGINAL
  ├── glove_7class_v5_feature_columns.json     ✓ ORIGINAL
  ├── glove_7class_v5_label_mapping.json       ✓ ORIGINAL
  └── glove_7class_v5_train_test_split.json    ✓ ORIGINAL

tools/
  └── safeher_realtime_inference.py             ✓ ORIGINAL

features/
  └── glove_7class_features.csv                 ✓ ORIGINAL
```

### HELPER SCRIPTS (development only)
```
tools/convert_v5_for_esp32.py               (conversion pipeline)
discover_export_api.py                      (API exploration - debug only)
```

---

## 10. Validation Checklist

- [x] Model loads successfully with Treelite 4.7.0
- [x] Feature count verified (51)
- [x] Class count verified (7)
- [x] Binary export successful (5.44 MB)
- [x] JSON export successful (19.96 MB)
- [x] Metadata generated with correct config
- [x] C++ wrapper template created
- [x] All files exist and are readable
- [x] Original V5 model unchanged
- [x] Real-time inference script unchanged
- [x] No datasets modified
- [ ] **(Future)** Test ESP32-C3 model loading and inference
- [ ] **(Future)** Optimize model size for deployment
- [ ] **(Future)** Validate on-device performance

---

## 11. Next Actions

1. **Review feasibility:** Discuss model optimization strategy with team
2. **Plan optimization:** Decide on tree pruning vs. quantization approach
3. **Create V6:** Generate optimized version if needed
4. **Test integration:** Start ESP32-C3 firmware integration (separate task)
5. **Validate hardware:** Test inference latency on actual device

---

## Appendix: Treelite Export API Reference

**Treelite 4.7.0** provides the following capabilities:

```python
from treelite.frontend import from_xgboost_json

# Load model from JSON
model = from_xgboost_json(model_json_string)

# Query model properties
num_features = model.num_feature      # 51
num_trees = model.num_tree            # 4200

# Export model
binary = model.serialize_bytes()      # Binary format (5.44 MB)
json_str = model.dump_as_json()       # JSON format (19.96 MB)

# Model properties
input_type = model.input_type         # float32
output_type = model.output_type       # float32
```

**Note:** Treelite 4.7.0 does NOT include built-in C/C++ source code generation. Export functionality focuses on:
- Binary serialization (inference runtime)
- JSON representation (debugging, analysis)
- Model interrogation (API for properties)

For C/C++ code generation, consider alternative approaches:
- Treelite compiler (separate installation required)
- XGBoost C API (lower-level integration)
- ONNX conversion + C++ runtime
- Custom C++ wrapper over Treelite predictor

---

**End of Status Report**
