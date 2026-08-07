"""
Configuration utilities for SafeHer backend
"""
import os
from pathlib import Path

# Project root
PROJECT_ROOT = Path(__file__).parent.parent.parent

# Directories
DATASETS_DIR = PROJECT_ROOT / 'datasets'
MODELS_DIR = PROJECT_ROOT / 'cloud_functions'
ML_TRAINING_DIR = PROJECT_ROOT / 'ml_training'
OUTPUTS_DIR = ML_TRAINING_DIR / 'outputs'

# Create directories if they don't exist
OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)

# Model paths
MOTION_MODEL_DIR = MODELS_DIR / 'motion_detection' / 'models'
WEAPON_MODEL_DIR = MODELS_DIR / 'weapon_detection' / 'models'
VOICE_MODEL_DIR = MODELS_DIR / 'voice_detection' / 'models'

# Dataset paths
MOTION_DATASET_DIR = DATASETS_DIR / 'motion_detection'
WEAPON_DATASET_DIR = DATASETS_DIR / 'weapon_detection'
VOICE_DATASET_DIR = DATASETS_DIR / 'voice_detection'

# Training configs
RANDOM_SEED = 42
DEFAULT_TEST_SIZE = 0.2

def get_project_root():
    """Get project root directory"""
    return PROJECT_ROOT

def get_dataset_path(dataset_name):
    """Get dataset path by name"""
    return DATASETS_DIR / dataset_name

def get_model_path(model_name):
    """Get model deployment path"""
    paths = {
        'motion': MOTION_MODEL_DIR,
        'weapon': WEAPON_MODEL_DIR,
        'voice': VOICE_MODEL_DIR
    }
    return paths.get(model_name)
