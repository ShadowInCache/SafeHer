// SafeHer V5 XGBoost Embedded Model - Compact C++ Arrays
// Auto-generated from XGBoost JSON model
//
// This header contains compact array-based representations of all 4200 decision trees
// suitable for embedded inference on ESP32-C3 and similar microcontrollers.
//
// Model Specification:
// - Trees: 4200
// - Classes: 7
// - Features: 51
// - Total Nodes: 62804
// - Max Depth: 6
//
// WARNING: DO NOT EDIT MANUALLY - This is an auto-generated file
// Changes should be made through convert_v5_to_embedded_arrays.py

#pragma once

#include <cstdint>
#include <cstring>
#include <algorithm>
#include <cmath>

namespace SafeHer {
namespace V5Embedded {

// ============================================================================
// MODEL CONSTANTS
// ============================================================================

constexpr int NUM_TREES = 4200;
constexpr int NUM_CLASSES = 7;
constexpr int NUM_FEATURES = 51;
constexpr int TOTAL_NODES = 62804;
constexpr int MAX_TREE_NODES = 2048;  // Maximum nodes in any single tree

// ============================================================================
// NODE STRUCTURE (Compact representation)
// ============================================================================

struct TreeNode {
    int16_t feature_idx;     // Feature index for split (-1 for leaf)
    float threshold;         // Split threshold value
    int16_t left_child;      // Index of left child node (-1 if leaf)
    int16_t right_child;     // Index of right child node (-1 if leaf)
    float leaf_value;        // Prediction value (for leaf nodes)

    bool is_leaf() const { return feature_idx == -1; }
};

// ============================================================================
// TREE DATA
// ============================================================================

// Tree offsets: where each tree starts in the node array
extern const int32_t tree_offsets[NUM_TREES];

// All nodes from all trees in contiguous array
extern const TreeNode tree_nodes[TOTAL_NODES];

// ============================================================================
// INFERENCE FUNCTIONS
// ============================================================================

/**
 * Evaluate a single tree on a feature vector.
 *
 * @param tree_id Index of the tree to evaluate (0 to NUM_TREES-1)
 * @param features Feature vector (size NUM_FEATURES)
 * @return Prediction value from the tree leaf
 */
float evaluate_tree(int tree_id, const float* features);

/**
 * Evaluate all trees (full inference).
 * Accumulates predictions from all trees by class.
 *
 * @param features Feature vector (size NUM_FEATURES)
 * @param output Output array (size NUM_CLASSES) for accumulated scores
 */
void evaluate_forest(const float* features, float* output);

/**
 * Get predicted class from accumulated scores.
 * Applies softmax and returns argmax class.
 *
 * @param scores Accumulated scores (size NUM_CLASSES)
 * @return Predicted class index (0 to NUM_CLASSES-1)
 */
int predict_class(const float* scores);

/**
 * Get confidence for predicted class.
 * Applies softmax to scores and returns max probability.
 *
 * @param scores Accumulated scores (size NUM_CLASSES)
 * @return Confidence (probability) of predicted class (0.0 to 1.0)
 */
float predict_confidence(const float* scores);

}  // namespace V5Embedded
}  // namespace SafeHer
